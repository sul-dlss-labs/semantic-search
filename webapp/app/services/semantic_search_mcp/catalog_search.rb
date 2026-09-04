# frozen_string_literal: true

module SemanticSearchMcp
  # Catalog search functionality exposed through MCP.
  module CatalogSearch
    extend self

    SEARCH_TYPES = %w[keyword vector hybrid].freeze
    MATCHED_CHUNKS_PER_DOCUMENT = 3
    MATCHED_CHUNK_TOP_K = 250

    def build_input_schema
      properties = {
        query: {
          type: "string",
          description: "The search query to find materials in the catalog. For the first vector or hybrid search, pass the " \
                       "user's current natural-language question verbatim; only rephrase it on a later fallback attempt."
        },
        search_type: {
          type: "string",
          description: "The search strategy to use. Chat clients should explicitly use vector for most discovery questions; " \
                       "use keyword only for exact terms and hybrid only when both strategies are intentionally needed.",
          enum: SEARCH_TYPES,
          default: "hybrid"
        },
        rows: {
          type: "integer",
          description: "Number of results to return (max 20)",
          minimum: 1,
          maximum: 20,
          default: 10
        }
      }
      filter_properties = facet_options.transform_values do |options|
        { type: "string", description: options[:description] }
      end
      properties[:filters] = filter_schema(filter_properties) if filter_properties.any?

      {
        type: "object",
        properties: properties,
        required: [ "query" ],
        additionalProperties: false
      }
    end

    def build_output_schema
      {
        type: "object",
        properties: {
          query: { type: "string" },
          search_type: { type: "string", enum: SEARCH_TYPES },
          filters: { type: "object", additionalProperties: { type: "string" } },
          total: { type: "integer", minimum: 0 },
          results: { type: "array", items: catalog_result_schema },
          facets: { type: "object", additionalProperties: facet_schema }
        },
        required: %w[query search_type filters total results facets],
        additionalProperties: false
      }
    end

    def search(query:, search_type: "hybrid", rows: 10, filters: {}, controller: nil)
      config = CatalogController.blacklight_config
      params = search_params(query, search_type, rows, filters)
      state = Blacklight::SearchState.new(params, config, controller)
      search_builder = nil
      response = Blacklight::SearchService.new(config: config, search_state: state).search_results do |builder|
        search_builder = builder
      end
      matched_chunks = matched_chunks(response.documents, search_builder&.query_embedding, config)

      CatalogResults.format(
        response: response,
        query: query,
        search_type: search_type,
        filters: filters || {},
        config: config,
        controller: controller,
        matched_chunks: matched_chunks
      )
    rescue StandardError => e
      SemanticSearchMcp.internal_error("Catalog search failed.", e)
    end

    private

    def catalog_result_schema
      {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
          authors: { type: "array", items: { type: "string" } },
          format: { type: "string" },
          created: { type: "string" },
          collection: { type: "string" },
          child_count: { type: "integer", minimum: 0 },
          matched_chunks: { type: "array", items: matched_chunk_schema },
          url: { type: "string" }
        },
        required: %w[id title url],
        additionalProperties: false
      }
    end

    def matched_chunk_schema
      {
        type: "object",
        properties: {
          text: { type: "string" },
          filename: { type: "string" },
          chunk_index: { type: "integer", minimum: 0 },
          page: { type: "string" },
          score: { type: "number" }
        },
        additionalProperties: false
      }
    end

    def facet_schema
      {
        type: "object",
        properties: {
          label: { type: "string" },
          values: {
            type: "array",
            items: {
              type: "object",
              properties: {
                value: { type: "string" },
                count: { type: "integer", minimum: 0 }
              },
              required: %w[value count],
              additionalProperties: false
            }
          }
        },
        required: %w[label values],
        additionalProperties: false
      }
    end

    def matched_chunks(documents, embedding, config)
      parent_ids = Array(documents).filter_map { |document| document.id || document["id"] }.to_set
      return {} if embedding.blank? || parent_ids.empty?

      response = config.repository.search(params: matched_chunk_query(embedding))
      response.documents.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |chunk, matches|
        parent_id = parent_id_for(chunk, parent_ids)
        next unless parent_id
        next if matches[parent_id].length >= MATCHED_CHUNKS_PER_DOCUMENT

        matches[parent_id] << {
          text: chunk["chunk_text_tesi"],
          filename: chunk["filename_ss"],
          chunk_index: chunk["chunk_index_i"],
          page: chunk["page_ss"],
          score: chunk["score"]
        }.compact
      end
    end

    def parent_id_for(chunk, parent_ids)
      stored_root = chunk["_root_"]
      return stored_root if parent_ids.include?(stored_root)

      child_id = chunk.id || chunk["id"]
      parent_ids.find { |parent_id| child_id&.start_with?("#{parent_id}_") }
    end

    def matched_chunk_query(embedding)
      {
        facet: false,
        json: {
          query: {
            knn: {
              f: "vector",
              topK: MATCHED_CHUNK_TOP_K,
              query: "[#{embedding.join(', ')}]"
            }
          },
          fields: %w[id chunk_text_tesi filename_ss chunk_index_i page_ss score],
          limit: MATCHED_CHUNK_TOP_K
        }
      }
    end

    def facet_options
      used_keys = Set.new
      CatalogController.blacklight_config.facet_fields.each_with_object({}) do |(field_name, config), options|
        next unless usable_facet?(config)

        key = unique_key(clean_label(config.label), field_name, used_keys)
        used_keys << key
        options[key] = {
          field: config.field || field_name,
          description: "Filter by #{config.label.downcase}"
        }
      end
    end

    def usable_facet?(config)
      config.show != false && config.label.present? && config.query.blank? && config.pivot.blank? && config.range != true
    end

    def unique_key(label_key, field_name, used_keys)
      return label_key unless used_keys.include?(label_key)

      clean_label(field_name)
    end

    def clean_label(label)
      label.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
    end

    def filter_schema(properties)
      {
        type: "object",
        description: "Optional filters to narrow search results",
        properties: properties,
        additionalProperties: false
      }
    end

    def search_params(query, search_type, rows, filters)
      {
        q: query,
        search_field: "all_fields",
        search_type: SEARCH_TYPES.include?(search_type) ? search_type : "hybrid",
        rows: [ [ rows, 1 ].max, 20 ].min
      }.tap do |params|
        params[:f] = mapped_filters(filters) if filters.present?
      end
    end

    def mapped_filters(filters)
      options = facet_options
      filters.each_with_object({}) do |(key, value), mapped|
        field = options.dig(key.to_s, :field)
        mapped[field] = [ value ] if field
      end
    end
  end
end
