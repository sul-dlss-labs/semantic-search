# frozen_string_literal: true

require "base64"

module SemanticSearchMcp
  # Retrieves all text chunks belonging to a catalog document in stable order.
  module DocumentChunks
    extend self

    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100
    CURSOR_VERSION = 1
    FIELDS = %w[id chunk_text_tesi filename_ss chunk_index_i page_ss].freeze

    def build_input_schema
      {
        type: "object",
        properties: {
          document_id: {
            type: "string",
            description: "Catalog document identifier whose text chunks should be retrieved",
            minLength: 1
          },
          limit: {
            type: "integer",
            description: "Number of chunks to return per call (max #{MAX_LIMIT})",
            minimum: 1,
            maximum: MAX_LIMIT,
            default: DEFAULT_LIMIT
          },
          cursor: {
            type: "string",
            description: "Opaque continuation cursor returned by a previous call for this document"
          }
        },
        required: [ "document_id" ],
        additionalProperties: false
      }
    end

    def build_output_schema
      {
        type: "object",
        properties: {
          document_id: { type: "string" },
          url: { type: "string" },
          total_chunks: { type: "integer", minimum: 0 },
          returned_chunks: { type: "integer", minimum: 0 },
          chunks: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: { type: "string" },
                text: { type: "string" },
                filename: { type: "string" },
                chunk_index: { type: "integer", minimum: 0 },
                page: { type: "string" }
              },
              required: [ "id" ],
              additionalProperties: false
            }
          },
          next_cursor: { type: [ "string", "null" ] },
          complete: { type: "boolean" }
        },
        required: %w[document_id url total_chunks returned_chunks chunks next_cursor complete],
        additionalProperties: false
      }
    end

    def retrieve(document_id:, limit: DEFAULT_LIMIT, cursor: nil, controller: nil)
      limit = normalized_limit(limit)
      offset = decode_cursor(cursor, document_id)
      response = CatalogController.blacklight_config.repository.search(
        params: solr_query(document_id, limit, offset)
      )
      chunks = response.documents.map { |document| format_chunk(document) }
      next_offset = offset + chunks.length
      complete = next_offset >= response.total

      structured_content = {
        document_id: document_id,
        url: record_url(controller, document_id),
        total_chunks: response.total,
        returned_chunks: chunks.length,
        chunks: chunks,
        next_cursor: complete ? nil : encode_cursor(document_id, next_offset),
        complete: complete
      }

      {
        text: result_text(structured_content),
        structured_content: structured_content
      }
    rescue ArgumentError => e
      error_result(e.message)
    rescue StandardError => e
      SemanticSearchMcp.internal_error("Document chunks could not be retrieved.", e)
    end

    private

    def solr_query(document_id, limit, offset)
      {
        q: "_root_:#{RSolr.solr_escape(document_id)}",
        fq: "doc_type_ssi:child",
        fl: FIELDS.join(","),
        sort: "filename_ss asc, chunk_index_i asc, id asc",
        rows: limit,
        start: offset,
        facet: false
      }
    end

    def format_chunk(document)
      {
        id: document.id || document["id"],
        text: document["chunk_text_tesi"],
        filename: document["filename_ss"],
        chunk_index: document["chunk_index_i"],
        page: document["page_ss"]
      }.compact
    end

    def normalized_limit(limit)
      [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
    end

    def encode_cursor(document_id, offset)
      payload = { version: CURSOR_VERSION, document_id: document_id, offset: offset }.to_json
      Base64.urlsafe_encode64(payload, padding: false)
    end

    def decode_cursor(cursor, document_id)
      return 0 if cursor.blank?

      payload = JSON.parse(Base64.urlsafe_decode64(cursor))
      valid = payload["version"] == CURSOR_VERSION &&
              payload["document_id"] == document_id &&
              payload["offset"].is_a?(Integer) &&
              payload["offset"] >= 0
      raise ArgumentError, "Invalid cursor for document #{document_id}" unless valid

      payload["offset"]
    rescue JSON::ParserError, ArgumentError
      raise ArgumentError, "Invalid cursor for document #{document_id}"
    end

    def record_url(controller, document_id)
      return controller.solr_document_url(document_id) if controller

      Rails.application.routes.url_helpers.solr_document_path(document_id)
    end

    def result_text(result)
      coverage = "#{result[:returned_chunks]} of #{result[:total_chunks]} chunks"
      lines = [ "Document #{result[:document_id]}: #{coverage} (complete: #{result[:complete]})" ]
      result[:chunks].each do |chunk|
        source = [
          chunk[:filename],
          chunk[:page] && "page #{chunk[:page]}",
          chunk[:chunk_index] && "chunk #{chunk[:chunk_index]}"
        ].compact.join(", ")
        lines << "\n[#{source}]\n#{chunk[:text]}"
      end
      lines << "\nContinue with cursor: #{result[:next_cursor]}" if result[:next_cursor]
      lines.join("\n")
    end

    def error_result(message)
      { text: message, structured_content: { error: message }, error: true }
    end
  end
end
