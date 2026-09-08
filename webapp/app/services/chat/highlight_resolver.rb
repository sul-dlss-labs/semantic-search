# frozen_string_literal: true

module Chat
  # Turns cited pages into viewer highlights, keeping only phrases IIIF Content Search confirms.
  #
  # A confirmed phrase that occurs on exactly one canvas also gives us that canvas id, which is a more
  # reliable target than the page number: page_ss restarts at 1 for every source file, so the
  # canvas_index = page - 1 mapping is wrong for objects built from more than one file.
  class HighlightResolver
    MAX_REQUESTS = 8
    MAX_SECONDS = 2.0

    def initialize(source_collection:, client: ContentSearchClient.new, selector: HighlightSelector.new)
      @source_collection = source_collection
      @client = client
      @selector = selector
    end

    # @return [Hash] { url => { "17" => { phrase:, canvas_id: } } }, only for confirmed phrases
    def call(sources, answer)
      return {} unless Rails.configuration.x.chat.highlight_verification

      @requests = 0
      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MAX_SECONDS

      Array(sources).each_with_object({}) do |source, highlights|
        evidence = @source_collection.evidence_for(source[:url])
        next if evidence.blank?

        pages = resolve_pages(source, evidence, answer)
        highlights[source[:url]] = pages if pages.any?
      end
    end

    private

    def resolve_pages(source, evidence, answer)
      Array(source[:pages]).each_with_object({}) do |page, pages|
        break pages if budget_spent?

        chunk_texts = evidence[:pages][page]
        next if chunk_texts.blank?

        highlight = resolve_page(evidence[:document_id], chunk_texts, focus_text(answer, source, page))
        pages[page] = highlight if highlight
      end
    end

    def resolve_page(document_id, chunk_texts, focus_text)
      candidates = @selector.call(chunk_texts:, focus_text:).first(attempts_per_page)

      candidates.each do |phrase|
        break if budget_spent?

        @requests += 1
        canvas_ids = @client.canvas_ids(druid: document_id, phrase:)
        next if canvas_ids.blank?

        # Several matches cannot tell us which canvas the answer meant; the existing canvas_index still
        # targets the cited page, and sul-embed selects the first hit on it.
        return { phrase:, canvas_id: (canvas_ids.first if canvas_ids.one?) }.compact
      end

      nil
    end

    def attempts_per_page
      Rails.configuration.x.chat.highlight_attempts_per_page || 1
    end

    def budget_spent?
      @requests >= MAX_REQUESTS || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
    end

    # Bias the phrase toward the sentence that actually makes the claim, rather than the top of the chunk.
    def focus_text(answer, source, page)
      sentences = answer.to_s.split(/(?<=[.!?])\s+/)
      page_reference = /\bpp?\.\s*#{Regexp.escape(page)}\b/
      citing = sentences.select do |sentence|
        sentence.include?(source[:title].to_s) || page_reference.match?(sentence)
      end

      citing.any? ? citing.join(" ") : answer.to_s
    end
  end
end
