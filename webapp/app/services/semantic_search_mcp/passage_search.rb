# frozen_string_literal: true

module SemanticSearchMcp
  # Searches child-document embeddings and enriches each passage with its parent source.
  module PassageSearch
    extend self

    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50
    PASSAGE_FIELDS = %w[id chunk_text_tesi filename_ss chunk_index_i page_ss score].freeze
    PARENT_FIELDS = %w[id title_display_tesi title_tesi title_tsim collection_title_ss].freeze

    def build_input_schema
      {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "Natural-language description of passages to find. On the first passage search, pass the user's " \
                         "current question verbatim; only rephrase it on a later fallback attempt.",
            minLength: 1
          },
          document_ids: {
            type: "array",
            description: "Optional document identifiers to search within",
            items: { type: "string" },
            uniqueItems: true
          },
          exclude_document_ids: {
            type: "array",
            description: "Optional document identifiers to exclude from the search",
            items: { type: "string" },
            uniqueItems: true
          },
          limit: {
            type: "integer",
            description: "Number of vector-ranked passages to return (max #{MAX_LIMIT})",
            minimum: 1,
            maximum: MAX_LIMIT,
            default: DEFAULT_LIMIT
          }
        },
        required: [ "query" ],
        additionalProperties: false
      }
    end

    def build_output_schema
      {
        type: "object",
        properties: {
          query: { type: "string" },
          search_type: { const: "vector" },
          returned_passages: { type: "integer", minimum: 0 },
          passages: {
            type: "array",
            items: {
              type: "object",
              properties: {
                rank: { type: "integer", minimum: 1 },
                text: { type: "string" },
                score: { type: "number" },
                chunk_id: { type: "string" },
                chunk_index: { type: "integer", minimum: 0 },
                filename: { type: "string" },
                page: { type: "string" },
                document_id: { type: "string" },
                document_title: { type: "string" },
                collection: { type: "string" },
                url: { type: "string" }
              },
              required: [ "rank" ],
              additionalProperties: false
            }
          }
        },
        required: %w[query search_type returned_passages passages],
        additionalProperties: false
      }
    end

    def search(query:, document_ids: [], exclude_document_ids: [], limit: DEFAULT_LIMIT, controller: nil)
      limit = normalized_limit(limit)
      embedding = query_embedding(query)
      response = CatalogController.blacklight_config.repository.search(
        params: solr_query(embedding, document_ids, exclude_document_ids, limit)
      )
      passage_documents = response.documents
      parent_ids = passage_documents.filter_map { |document| parent_id(document) }.uniq
      parents = fetch_parents(parent_ids)
      passages = passage_documents.map.with_index(1) do |document, rank|
        format_passage(document, rank, parents, controller)
      end

      structured_content = {
        query: query,
        search_type: "vector",
        returned_passages: passages.length,
        passages: passages
      }

      {
        text: result_text(structured_content),
        structured_content: structured_content
      }
    rescue StandardError => e
      SemanticSearchMcp.internal_error("Passage search failed.", e)
    end

    private

    def query_embedding(query)
      Rails.cache.fetch("embedding/#{query}") do
        GeminiEmbedding.new.embedding(
          input: [ query ],
          instruction: GeminiEmbedding::DEFAULT_QUERY_INSTRUCTION
        ).first
      end
    end

    def solr_query(embedding, document_ids, exclude_document_ids, limit)
      {
        facet: false,
        json: {
          query: {
            knn: {
              f: "vector",
              topK: limit,
              preFilter: pre_filters(document_ids, exclude_document_ids),
              query: "[#{embedding.join(', ')}]"
            }.compact
          },
          fields: PASSAGE_FIELDS,
          limit: limit
        }
      }
    end

    def pre_filters(document_ids, exclude_document_ids)
      filters = [ "doc_type_ssi:child" ]
      filters << root_filter(document_ids) if document_ids.present?
      filters << "-#{root_filter(exclude_document_ids)}" if exclude_document_ids.present?
      filters
    end

    def root_filter(document_ids)
      escaped_ids = document_ids.map { |id| RSolr.solr_escape(id) }
      "_root_:(#{escaped_ids.join(' OR ')})"
    end

    def fetch_parents(parent_ids)
      return {} if parent_ids.empty?

      response = CatalogController.blacklight_config.repository.search(
        params: {
          q: "id:(#{parent_ids.map { |id| RSolr.solr_escape(id) }.join(' OR ')})",
          fq: "doc_type_ssi:parent",
          fl: PARENT_FIELDS.join(","),
          rows: parent_ids.length,
          facet: false
        }
      )
      response.documents.index_by { |document| document.id || document["id"] }
    end

    def parent_id(document)
      child_id = document.id || document["id"]
      child_id&.split("_", 2)&.first
    end

    def format_passage(document, rank, parents, controller)
      document_id = parent_id(document)
      parent = parents[document_id]
      {
        rank: rank,
        text: document["chunk_text_tesi"],
        score: document["score"],
        chunk_id: document.id || document["id"],
        chunk_index: document["chunk_index_i"],
        filename: document["filename_ss"],
        page: document["page_ss"],
        document_id: document_id,
        document_title: field_value(parent, %w[title_display_tesi title_tesi title_tsim]),
        collection: field_value(parent, [ "collection_title_ss" ]),
        url: record_url(controller, document_id)
      }.compact
    end

    def field_value(document, field_names)
      return unless document

      field_names.each do |field_name|
        value = document[field_name]
        return value.first if value.is_a?(Array) && value.any?
        return value if value.present?
      end
      nil
    end

    def record_url(controller, document_id)
      return unless document_id
      return controller.solr_document_url(document_id) if controller

      Rails.application.routes.url_helpers.solr_document_path(document_id)
    end

    def normalized_limit(limit)
      [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
    end

    def result_text(result)
      return "No passages found for query: #{result[:query]}" if result[:passages].empty?

      header = "Found #{result[:returned_passages]} vector-ranked passages for query: #{result[:query]}"
      passages = result[:passages].map do |passage|
        source = passage[:document_title] || passage[:document_id] || "Unknown document"
        location = [
          passage[:filename],
          passage[:page] && "page #{passage[:page]}",
          passage[:chunk_index] && "chunk #{passage[:chunk_index]}"
        ].compact.join(", ")
        "#{passage[:rank]}. #{source} (#{location}, score #{passage[:score]})\n" \
          "   #{passage[:text]}\n" \
          "   Source: #{passage[:url]}"
      end
      "#{header}\n\n#{passages.join("\n\n")}"
    end

    def error_result(message)
      { text: message, structured_content: { error: message }, error: true }
    end
  end
end
