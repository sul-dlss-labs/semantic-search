# frozen_string_literal: true

require "json"

module Chat
  # Collects, deduplicates, and bounds sources returned by chat tools.
  class SourceCollection
    Selection = Data.define(:sources, :emitted_sources, :truncated) do
      def truncated?
        truncated
      end
    end

    LIMIT_MESSAGE = "Your query returned more research than can be displayed at once. " \
                    "Some sources were omitted from the source list; the answer uses the retrieved evidence."

    # Retained chunk text is only ever read server-side, to pick a highlight phrase. It is bounded to the
    # excerpt length the model itself saw (ToolResultCompactor::MAX_EXCERPT_CHARACTERS) so a highlight can
    # never come from text that was not part of the evidence.
    MAX_EVIDENCE_CHARACTERS = 1_000
    MAX_EVIDENCE_TEXTS_PER_PAGE = 2
    MAX_EVIDENCE_PAGES = 40

    def initialize
      @sources = []
      @evidence = {}
    end

    def add(content)
      return unless content.is_a?(Hash)

      content = content.deep_symbolize_keys
      candidates = Array(content[:results]).map do |result|
        {
          title: result[:title],
          url: result[:url],
          document_id: result[:id],
          chunks: Array(result[:matched_chunks])
        }
      end
      candidates.concat(
        Array(content[:passages]).map do |passage|
          {
            title: passage[:document_title] || passage[:document_id] || "Catalog record",
            url: passage[:url],
            document_id: passage[:document_id],
            chunks: [ passage ]
          }
        end
      )
      if content[:document_id] && content[:url]
        candidates << {
          title: "Document #{content[:document_id]}",
          url: content[:url],
          document_id: content[:document_id],
          chunks: Array(content[:chunks])
        }
      end

      candidates.each { |candidate| add_candidate(candidate) }
    end

    def for_answer(answer)
      cited_sources = @sources.select do |source|
        answer.include?(source.fetch(:title)) || answer.include?(source.fetch(:url))
      end

      sources = (cited_sources + @sources.first(10)).uniq { |source| source.fetch(:url) }
      emitted_sources = bounded_sources(sources)
      Selection.new(sources:, emitted_sources:, truncated: emitted_sources.length < sources.length)
    end

    # @return [Hash, nil] { document_id:, pages: { "17" => [text, ...] } } for a source URL
    def evidence_for(url)
      @evidence[url]
    end

    private

    def add_candidate(candidate)
      return if candidate[:title].blank? || candidate[:url].blank?

      pages = pages_from(candidate[:chunks])
      record_evidence(candidate)

      existing_source = @sources.find { |source| source[:url] == candidate[:url] }
      if existing_source
        merge_pages(existing_source, pages)
        return
      end

      source = { title: candidate[:title], url: candidate[:url] }
      source[:pages] = pages if pages.any?
      @sources << source
    end

    def record_evidence(candidate)
      entry = (@evidence[candidate[:url]] ||= { document_id: candidate[:document_id], pages: {} })
      entry[:document_id] ||= candidate[:document_id]

      Array(candidate[:chunks]).each do |chunk|
        next unless chunk.is_a?(Hash)

        text = chunk[:text].to_s
        next if text.blank?

        Array(chunk[:page]).compact_blank.map(&:to_s).uniq.each do |page|
          texts = entry[:pages][page]
          next if texts.nil? && entry[:pages].length >= MAX_EVIDENCE_PAGES

          texts ||= (entry[:pages][page] = [])
          next if texts.length >= MAX_EVIDENCE_TEXTS_PER_PAGE

          excerpt = text.first(MAX_EVIDENCE_CHARACTERS)
          texts << excerpt unless texts.include?(excerpt)
        end
      end
    end

    def pages_from(chunks)
      Array(chunks).flat_map { |chunk| Array(chunk[:page]) }.compact_blank.map(&:to_s).uniq
    end

    def merge_pages(source, pages)
      return if pages.empty?

      source[:pages] = (Array(source[:pages]) + pages).uniq
    end

    def bounded_sources(sources)
      emitted_sources = []
      emitted_characters = 0
      sources.each do |source|
        break if emitted_sources.length >= Rails.configuration.x.chat.max_sources

        source_characters = JSON.generate(source).bytesize
        if emitted_sources.any? &&
           emitted_characters + source_characters > Rails.configuration.x.chat.max_source_event_characters
          break
        end

        emitted_sources << source
        emitted_characters += source_characters
      end
      emitted_sources
    end
  end
end
