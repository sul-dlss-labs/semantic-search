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

    def initialize
      @sources = []
      # Documents carried in from a results page. Kept apart from @sources so they can be cited
      # as verified links without displacing genuinely retrieved sources.
      @seeded = []
    end

    def add(content)
      collect(content, @sources)
    end

    def seed(content)
      collect(content, @seeded)
    end

    def for_answer(answer)
      cited_sources = (@sources + @seeded).select do |source|
        answer.include?(source.fetch(:title)) || answer.include?(source.fetch(:url))
      end

      # The floor draws from retrieved sources only, so a seeded document reaches the browser
      # only when the answer actually cites it.
      sources = (cited_sources + @sources.first(10)).uniq { |source| source.fetch(:url) }
      emitted_sources = bounded_sources(sources)
      Selection.new(sources:, emitted_sources:, truncated: emitted_sources.length < sources.length)
    end

    private

    def collect(content, into)
      return unless content.is_a?(Hash)

      content = content.deep_symbolize_keys
      candidates = Array(content[:results]).map do |result|
        { title: result[:title], url: result[:url], pages: pages_from(result[:matched_chunks]) }
      end
      candidates.concat(
        Array(content[:passages]).map do |passage|
          {
            title: passage[:document_title] || passage[:document_id] || "Catalog record",
            url: passage[:url],
            pages: pages_from([ passage ])
          }
        end
      )
      if content[:document_id] && content[:url]
        candidates << {
          title: "Document #{content[:document_id]}",
          url: content[:url],
          pages: pages_from(content[:chunks])
        }
      end

      candidates.each { |candidate| add_candidate(candidate, into) }
    end

    def add_candidate(candidate, into)
      return if candidate[:title].blank? || candidate[:url].blank?

      existing_source = promote(candidate[:url], into) || into.find { |source| source[:url] == candidate[:url] }
      if existing_source
        merge_pages(existing_source, candidate[:pages])
        return
      end

      source = { title: candidate[:title], url: candidate[:url] }
      source[:pages] = candidate[:pages] if candidate[:pages].any?
      into << source
    end

    # A seeded document a tool later returns was genuinely retrieved, so move it across tiers.
    def promote(url, into)
      return nil unless into.equal?(@sources)

      seeded_source = @seeded.find { |source| source[:url] == url }
      return nil if seeded_source.nil?

      @seeded.delete(seeded_source)
      @sources << seeded_source
      seeded_source
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
