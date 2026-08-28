# frozen_string_literal: true

require "set"

module Chat
  # Produces bounded, deduplicated evidence text for the model while preserving ranked order.
  class ToolResultCompactor
    MAX_CHARACTERS = 24_000
    MAX_EXCERPT_CHARACTERS = 2_000
    MAX_ITEMS_PER_TYPE = 20

    def initialize
      @seen = Set.new
    end

    def call(result)
      return result[:text].to_s.first(MAX_CHARACTERS) if result[:error]

      content = result[:structured_content].to_h.deep_symbolize_keys
      sections = [
        passage_text(content[:passages]),
        catalog_text(content[:results]),
        document_text(content)
      ].compact_blank
      text = if evidence_content?(content)
        sections.join("\n\n")
      else
        result[:text].to_s
      end
      text = "No new evidence; these results duplicate evidence already returned." if text.blank?
      bound(text)
    end

    private

    def evidence_content?(content)
      content.key?(:passages) || content.key?(:results) || content.key?(:chunks)
    end

    def passage_text(passages)
      entries = Array(passages).first(MAX_ITEMS_PER_TYPE).filter_map do |passage|
        passage = passage.deep_symbolize_keys
        next unless remember([ :passage, passage[:chunk_id], passage[:document_id], passage[:chunk_index] ])

        source = passage[:document_title] || passage[:document_id] || "Unknown document"
        location = location_text(passage)
        <<~TEXT.strip
          #{passage[:rank]}. #{source}#{location}
          #{excerpt(passage[:text])}
          Source: #{passage[:url]}
        TEXT
      end
      "Passage evidence:\n#{entries.join("\n\n")}" if entries.any?
    end

    def catalog_text(results)
      entries = Array(results).first(MAX_ITEMS_PER_TYPE).filter_map do |result|
        result = result.deep_symbolize_keys
        new_document = remember([ :document, result[:id] ])
        chunks = Array(result[:matched_chunks]).filter_map do |chunk|
          chunk = chunk.deep_symbolize_keys
          next unless remember([ :catalog_chunk, result[:id], chunk[:filename], chunk[:chunk_index] ])

          "-#{location_text(chunk)} #{excerpt(chunk[:text])}"
        end
        next unless new_document || chunks.any?

        lines = [ result[:title] || result[:id] || "Untitled" ]
        lines << "Authors: #{Array(result[:authors]).join(', ')}" if result[:authors].present?
        lines << "Collection: #{result[:collection]}" if result[:collection].present?
        lines << "Matched passages:\n#{chunks.join("\n")}" if chunks.any?
        lines << "Source: #{result[:url]}" if result[:url].present?
        lines.join("\n")
      end
      "Catalog evidence:\n#{entries.join("\n\n")}" if entries.any?
    end

    def document_text(content)
      return if content[:document_id].blank? || content[:chunks].blank?

      chunks = Array(content[:chunks]).first(MAX_ITEMS_PER_TYPE).filter_map do |chunk|
        chunk = chunk.deep_symbolize_keys
        next unless remember([ :document_chunk, chunk[:id] ])

        "#{location_text(chunk)}\n#{excerpt(chunk[:text])}"
      end
      return if chunks.empty?

      coverage = "#{content[:returned_chunks]} of #{content[:total_chunks]} chunks"
      lines = [ "Document #{content[:document_id]}: #{coverage} (complete: #{content[:complete]})", chunks.join("\n\n") ]
      lines << "Continue with cursor: #{content[:next_cursor]}" if content[:next_cursor].present?
      lines.join("\n\n")
    end

    def remember(key)
      return false if @seen.include?(key)

      @seen << key
      true
    end

    def location_text(item)
      values = [
        item[:filename],
        item[:page] && "page #{item[:page]}",
        item[:chunk_index] && "chunk #{item[:chunk_index]}"
      ].compact
      values.any? ? " (#{values.join(', ')})" : ""
    end

    def excerpt(text)
      text.to_s.truncate(MAX_EXCERPT_CHARACTERS, omission: "…")
    end

    def bound(text)
      return text if text.length <= MAX_CHARACTERS

      "#{text.first(MAX_CHARACTERS)}\n[Additional evidence omitted to keep the prompt bounded.]"
    end
  end
end
