# frozen_string_literal: true

module Chat
  # The page of search results a conversation was started from.
  #
  # Travels in two hops. The results page links to /chat with the plain Blacklight search params,
  # which this class re-runs to derive the context; the chat page then signs the derived context
  # into a token that the browser replays on every turn, so the search runs once per conversation
  # rather than once per turn and the browser never supplies context text that reaches the model.
  class SearchContext
    VERIFIER_PURPOSE = "chat-search-context"
    MAX_QUERY = 500
    MAX_TITLE = 200
    MAX_AUTHORS = 3
    MAX_AUTHOR = 120
    MAX_COLLECTION = 200

    # Blacklight's own allowlist covers the rest. Paging is not in search_state_fields, and it is
    # what makes "these results" mean the page the user was actually looking at.
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

    # @return [SearchContext, nil] nil for a missing, tampered, or expired token
    def self.from_token(token, controller: nil)
      return nil if token.blank?

      payload = verifier.verified(token.to_s)&.deep_symbolize_keys
      return nil unless payload&.dig(:version) == 1

      new(payload, controller:)
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

    # Re-wrapped as unpermitted parameters so Blacklight's allowlist does the filtering rather
    # than this class trusting whatever arrived in the URL.
    def self.search_state(attributes, controller)
      permitted = ActionController::Parameters.new(attributes.symbolize_keys)
      permitted[:search_field] = "all_fields"
      # CatalogController picks the search strategy in a prepend_before_action that ChatsController
      # never runs, so re-derive it here or the carried page would be ranked differently.
      permitted[:search_type] = CatalogSearchClassifier.new(permitted[:q]).call if permitted[:q].present?
      Blacklight::SearchState.new(permitted, CatalogController.blacklight_config, controller)
    end
    private_class_method :search_state

    def self.derive(state, controller)
      config = CatalogController.blacklight_config
      response = Blacklight::SearchService.new(config:, search_state: state).search_results
      # Reusing the MCP formatter is what guarantees carried documents get byte-identical titles
      # and URLs to the ones the chat tools return, so SourceCollection can dedupe them.
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

    # Query facets (Text chunks) store the query key rather than a displayable value. Their config
    # is keyed by string with symbol-keyed values, so neither a plain dig nor a symbol lookup works.
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

    # Collapsed before it reaches the prompt: a multi-line title inside the context block would
    # otherwise be indistinguishable from the surrounding structure.
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

    def initialize(payload, controller: nil)
      @payload = payload
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

    def documents
      @documents ||= Array(@payload[:documents]).map do |document|
        document.merge(url: SemanticSearchMcp::CatalogResults.record_url(@controller, document[:id]))
      end
    end

    def filters
      Array(@payload[:filters])
    end

    # Only the facets catalog_search_tool can actually express. Its filters take a single string
    # per field, so a multi-select facet contributes only its first value.
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

    # True when the user's page held more results than we are willing to carry.
    def truncated?
      documents.length < page_size
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
      # A search with no matches is exactly where the assistant's vector search can still help,
      # so point it at the topic rather than at results that do not exist.
      return "What can you find about #{quoted_query}?" if zero_results?

      "What do these results tell me about #{quoted_query}?"
    end

    # Quoted-phrase searches are a first-class pattern here, so wrapping blindly would render
    # ""like this"".
    def quoted_query
      return query if query.start_with?('"') && query.end_with?('"')

      %("#{query}")
    end
  end
end
