# frozen_string_literal: true

require "set"

module Chat
  # Produces bounded, deduplicated evidence text for the model while preserving ranked order.
  class ToolResultCompactor
    MAX_CHARACTERS = 24_000
    MAX_TOTAL_CHARACTERS = 40_000
    MAX_EXCERPT_CHARACTERS = 1_000
    MAX_ITEMS_PER_TYPE = 20
    MAX_CHUNKS_PER_RESULT = 1
    DUPLICATE_EVIDENCE_TEXT = "No new evidence; these results duplicate evidence already returned."
    BUDGET_REACHED_TEXT = "Evidence budget reached; answer using the evidence already returned."
    OMITTED_EVIDENCE_TEXT = "[Additional evidence omitted to keep the prompt bounded.]"

    def initialize(character_budget: MAX_TOTAL_CHARACTERS)
      @seen = Set.new
      @remaining_characters = character_budget
    end

    def call(result)
      return result[:text].to_s.first(MAX_CHARACTERS) if result[:error]
      # Checked before the sections are built so that exhausting the budget cannot mark evidence as
      # seen without ever sending it.
      return BUDGET_REACHED_TEXT if @remaining_characters <= 0

      content = result[:structured_content].to_h.deep_symbolize_keys
      @room = [ MAX_CHARACTERS, @remaining_characters ].min
      @room_exhausted = false
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
      consume(bound(annotate(text)))
    end

    private

    # Distinguishes "everything here was already sent" from "what is left did not fit", and tells the
    # model when a result was cut short so it knows more evidence exists.
    def annotate(text)
      return @room_exhausted ? BUDGET_REACHED_TEXT : DUPLICATE_EVIDENCE_TEXT if text.blank?
      return "#{text}\n#{OMITTED_EVIDENCE_TEXT}" if @room_exhausted

      text
    end

    def evidence_content?(content)
      content.key?(:passages) || content.key?(:results) || content.key?(:chunks)
    end

    def passage_text(passages)
      entries = Array(passages).first(MAX_ITEMS_PER_TYPE).filter_map do |passage|
        passage = passage.deep_symbolize_keys
        entry_for(chunk_key(passage)) do
          source = passage[:document_title] || passage[:document_id] || "Unknown document"
          location = location_text(passage)
          <<~TEXT.strip
            #{passage[:rank]}. #{source}#{location}
            #{excerpt(passage[:text])}
            Source: #{passage[:url]}
          TEXT
        end
      end
      "Passage evidence:\n#{entries.join("\n\n")}" if entries.any?
    end

    def catalog_text(results)
      entries = Array(results).first(MAX_ITEMS_PER_TYPE).filter_map do |result|
        result = result.deep_symbolize_keys
        document_key = [ :document, result[:id] ]
        chunks = matched_chunk_candidates(result)
        next if @seen.include?(document_key) && chunks.empty?

        lines = [ result[:title] || result[:id] || "Untitled" ]
        lines << "Authors: #{Array(result[:authors]).join(', ')}" if result[:authors].present?
        lines << "Collection: #{result[:collection]}" if result[:collection].present?
        lines << "Matched passages:\n#{chunks.pluck(:line).join("\n")}" if chunks.any?
        lines << "Source: #{result[:url]}" if result[:url].present?
        entry = lines.join("\n")
        next unless reserve_room(entry)

        @seen << document_key
        chunks.each { |chunk| @seen << chunk[:key] }
        entry
      end
      "Catalog evidence:\n#{entries.join("\n\n")}" if entries.any?
    end

    # Lazy so that a chunk beyond the per-result cap is never marked as seen, which would drop it
    # from every later tool result too.
    def matched_chunk_candidates(result)
      Array(result[:matched_chunks]).lazy.filter_map do |chunk|
        chunk = chunk.deep_symbolize_keys
        key = chunk_key(chunk, document_id: result[:id])
        next if @seen.include?(key)

        { key: key, line: "-#{location_text(chunk)} #{excerpt(chunk[:text])}" }
      end.first(MAX_CHUNKS_PER_RESULT)
    end

    def document_text(content)
      return if content[:document_id].blank? || content[:chunks].blank?

      chunks = Array(content[:chunks]).first(MAX_ITEMS_PER_TYPE).filter_map do |chunk|
        chunk = chunk.deep_symbolize_keys
        entry_for(chunk_key(chunk, document_id: content[:document_id])) do
          "#{location_text(chunk)}\n#{excerpt(chunk[:text])}"
        end
      end
      return if chunks.empty?

      coverage = "#{content[:returned_chunks]} of #{content[:total_chunks]} chunks"
      lines = [ "Document #{content[:document_id]}: #{coverage} (complete: #{content[:complete]})", chunks.join("\n\n") ]
      lines << "Continue with cursor: #{content[:next_cursor]}" if content[:next_cursor].present?
      lines.join("\n\n")
    end

    # Yields only for evidence that is both new and small enough to fit in what is left of this
    # message, and marks it seen only once it is really being sent.
    def entry_for(key)
      return if @seen.include?(key)

      entry = yield
      return if entry.blank? || !reserve_room(entry)

      @seen << key
      entry
    end

    # Evidence that does not fit is left unseen so a later tool result can carry it, rather than
    # being remembered and then truncated away by #bound.
    def reserve_room(entry)
      if entry.length > @room
        @room_exhausted = true
        return false
      end

      @room -= entry.length
      true
    end

    # One chunk reaches the model as a passage, as a catalog result's matched chunk, and as a
    # document chunk, each shaped differently. Identity is keyed on the filename first because a
    # catalog result's id is not always the document id its chunks carry.
    def chunk_key(chunk, document_id: nil)
      return [ :chunk, chunk[:filename], chunk[:chunk_index] ] if chunk[:filename].present?

      chunk_id = chunk[:chunk_id] || chunk[:id]
      return [ :chunk, chunk_id ] if chunk_id.present?

      [ :chunk, document_id || chunk[:document_id], chunk[:chunk_index], chunk[:page] ]
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
      limit = [ MAX_CHARACTERS, @remaining_characters ].min
      return text if text.length <= limit

      "#{text.first(limit)}\n[Additional evidence omitted to keep the prompt bounded.]"
    end

    def consume(text)
      @remaining_characters -= text.length
      text
    end
  end
end
