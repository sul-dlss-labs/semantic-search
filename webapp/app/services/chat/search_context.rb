# frozen_string_literal: true

module Chat
  # The page of search results a conversation was started from. Derived by re-running the search
  # params the results page links with, then signed into a token the browser replays each turn, so
  # the browser can never supply context text of its own.
  class SearchContext
    VERIFIER_PURPOSE = "chat-search-context"
    MAX_QUERY = 500
    MAX_TITLE = 200
    MAX_AUTHORS = 3
    MAX_AUTHOR = 120
    MAX_COLLECTION = 200

    # Not in Blacklight's search_state_fields, but paging is what scopes "these results" to a page.
    PAGING_FIELDS = %i[page per_page sort].freeze

    def self.verifier
      Rails.application.message_verifier(VERIFIER_PURPOSE)
    end

    # @return [SearchContext, nil] nil when there is nothing to carry, or the search cannot run
    def self.from_search_params(search_params, controller: nil)
      attributes = unwrap(search_params)
      return nil if attributes.blank?

      state = search_state(attributes, controller)
      return nil unless state.has_constraints?

      new(derive(state, controller), controller:)
    rescue StandardError => e
      Rails.logger.warn("Search context could not be derived: #{e.class}: #{e.message}")
      nil
    end

    # @param excluded_ids [Array<String>] dropped documents; safe from the browser because they
    #   can only subtract from the signed set
    # @return [SearchContext, nil] nil for a missing, tampered, or expired token
    def self.from_token(token, excluded_ids: nil, controller: nil)
      return nil if token.blank?

      payload = verifier.verified(token.to_s)&.deep_symbolize_keys
      return nil unless payload&.dig(:version) == 1

      new(payload, excluded_ids:, controller:)
    rescue StandardError => e
      Rails.logger.warn("Search context token could not be read: #{e.class}: #{e.message}")
      nil
    end

    def self.unwrap(search_params)
      return {} if search_params.blank?
      return search_params.to_unsafe_h if search_params.respond_to?(:to_unsafe_h)

      search_params.to_h
    end
    private_class_method :unwrap

    # Re-wrapped as unpermitted parameters so Blacklight's allowlist does the filtering.
    def self.search_state(attributes, controller)
      permitted = ActionController::Parameters.new(attributes.symbolize_keys)
      permitted[:search_field] = "all_fields"
      # CatalogController sets this in a prepend_before_action that ChatsController never runs.
      permitted[:search_type] = CatalogSearchClassifier.new(permitted[:q]).call if permitted[:q].present?
      Blacklight::SearchState.new(permitted, CatalogController.blacklight_config, controller)
    end
    private_class_method :search_state

    def self.derive(state, controller)
      config = CatalogController.blacklight_config
      response = Blacklight::SearchService.new(config:, search_state: state).search_results
      # Same formatter as the chat tools, so SourceCollection can dedupe carried against retrieved.
      formatted = SemanticSearchMcp::CatalogResults.format(
        response:, query: state.query_param.to_s, search_type: state.params[:search_type].to_s,
        filters: {}, config:, controller:
      ).dig(:structured_content, :results)

      {
        version: 1,
        query: state.query_param.to_s.truncate(MAX_QUERY).presence,
        search_type: state.params[:search_type].presence,
        page: state.page.to_i,
        per_page: state.per_page.to_i,
        total: response.total.to_i,
        page_size: Array(formatted).length,
        filters: filters_from(state),
        documents: Array(formatted).first(document_limit).map { |result| document_from(result) },
        search_params: state.to_h.except(:controller, :action)
      }
    end
    private_class_method :derive

    def self.filters_from(state)
      state.filters.map do |filter|
        values = Array(filter.values).select { |value| value.is_a?(String) }.map { |value| label_for(filter, value) }
        next if values.empty?

        {
          label: filter.config.label.to_s,
          values: values,
          tool_key: SemanticSearchMcp::CatalogSearch.filter_key_for(filter.config.field || filter.config.key)
        }
      end.compact
    end
    private_class_method :filters_from

    # Query facets store the query key, and their config is string-keyed with symbol-keyed values.
    def self.label_for(filter, value)
      filter.config.query.to_h[value.to_s].to_h[:label].presence || value
    end
    private_class_method :label_for

    def self.document_from(result)
      {
        id: result[:id],
        title: flatten(result[:title], MAX_TITLE),
        authors: Array(result[:authors]).first(MAX_AUTHORS).map { |author| flatten(author, MAX_AUTHOR) },
        collection: flatten(result[:collection], MAX_COLLECTION),
        date: year_of(result[:created])
      }.compact_blank
    end
    private_class_method :document_from

    # A multi-line title would be indistinguishable from the prompt's own structure.
    def self.flatten(value, limit)
      value.to_s.gsub(/\s+/, " ").strip.truncate(limit).presence
    end
    private_class_method :flatten

    def self.year_of(created)
      created.to_s[/\d{4}/]
    end
    private_class_method :year_of

    def self.document_limit
      Rails.configuration.x.chat.max_search_context_documents
    end
    private_class_method :document_limit

    def initialize(payload, excluded_ids: nil, controller: nil)
      @payload = payload
      @excluded_ids = Array(excluded_ids).grep(String)
      @controller = controller
    end

    def query = @payload[:query]
    def search_type = @payload[:search_type]
    def page = @payload[:page].to_i
    def per_page = @payload[:per_page].to_i
    def total = @payload[:total].to_i
    def page_size = @payload[:page_size].to_i

    def token
      self.class.verifier.generate(
        @payload, expires_in: Rails.configuration.x.chat.search_context_expires_in
      )
    end

    # Everything the token carries, including removed results. The prompt gets #documents instead.
    def carried_documents
      @carried_documents ||= Array(@payload[:documents]).map do |document|
        document.merge(url: SemanticSearchMcp::CatalogResults.record_url(@controller, document[:id]))
      end
    end

    def documents
      @documents ||= carried_documents.reject { |document| excluded_ids.include?(document[:id].to_s) }
    end

    def removed_count
      carried_documents.length - documents.length
    end

    def filters
      Array(@payload[:filters])
    end

    # catalog_search_tool takes one value per field, so a multi-select facet contributes its first.
    def tool_filters
      filters.filter_map do |filter|
        next if filter[:tool_key].blank?

        [ filter[:tool_key], filter[:values].first ]
      end.to_h
    end

    def seed_sources
      { results: documents.map { |document| { title: document[:title], url: document[:url] } } }
    end

    def search_params
      @payload[:search_params].to_h
    end

    def zero_results?
      total.zero?
    end

    # About the carry rather than #documents, so a removal does not read as a truncation.
    def truncated?
      carried_documents.length < page_size
    end

    def first_item
      return 0 if page_size.zero?

      ((page - 1) * per_page) + 1
    end

    def last_item
      first_item.zero? ? 0 : first_item + page_size - 1
    end

    def suggested_question
      return "What is in these results?" if query.blank?
      # Vector search can still help here, so point at the topic rather than absent results.
      return "What can you find about #{quoted_query}?" if zero_results?

      "What can these results tell me about #{quoted_query}?"
    end

    # Quoted-phrase searches are common here, so wrapping blindly would render ""like this"".
    def quoted_query
      return query if query.start_with?('"') && query.end_with?('"')

      %("#{query}")
    end

    private

    def excluded_ids
      @excluded_id_set ||= @excluded_ids.first(carried_documents.length).to_set
    end
  end
end
