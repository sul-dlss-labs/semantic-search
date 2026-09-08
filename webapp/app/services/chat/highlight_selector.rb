# frozen_string_literal: true

module Chat
  # Picks a short phrase from retrieved chunk text to highlight in the embedded viewer.
  #
  # IIIF Content Search matches phrases within a single OCR line: a phrase that spans a line break
  # returns no hits, and a word hyphenated across lines is indexed as two tokens. The ALTO extractor in
  # sdr-harvest emits one line per ALTO TextLine joined with "\n", and appends a de-hyphenated word to the
  # end of the preceding line, so both failure modes are avoidable here — candidates never cross a "\n",
  # and the last token of every line is discarded.
  class HighlightSelector
    WINDOW_SIZES = [ 5, 4, 3 ].freeze
    MAX_CANDIDATES = 3
    TOKEN = /[[:alnum:]]+(?:['’’-][[:alnum:]]+)*/

    STOPWORDS = %w[
      a about all also an and any are as at be been but by can do for from had has have he her his
      how i if in into is it its may more most no not of on one only or other our out over said she
      so some such than that the their them then there these they this to up was we were what when
      which who will with would you your
    ].to_set.freeze

    # @param chunk_texts [Array<String>] retrieved chunk text for one page
    # @param focus_text [String] the answer text citing this page, used to bias toward the claim
    # @return [Array<String>] up to MAX_CANDIDATES phrases, best first
    def call(chunk_texts:, focus_text: "")
      focus_tokens = content_tokens(focus_text)
      candidates = {}

      Array(chunk_texts).each do |chunk_text|
        chunk_text.to_s.split("\n").each do |line|
          tokens = line_tokens(line)
          next if tokens.length < WINDOW_SIZES.min

          windows(tokens).each do |window, offset|
            phrase = window.join(" ")
            next if candidates.key?(phrase.downcase)

            candidates[phrase.downcase] = { phrase:, score: score(window, focus_tokens), offset: }
          end
        end
      end

      candidates
        .values
        .sort_by { |candidate| [ -candidate[:score], candidate[:offset] ] }
        .first(MAX_CANDIDATES)
        .pluck(:phrase)
    end

    private

    # Tokens stay contiguous: dropping short words from the middle of a line would produce a phrase that
    # is not actually in the text. Only the trailing token goes, because it may be a de-hyphenation join.
    def line_tokens(line)
      plain(line).scan(TOKEN)[0..-2].to_a
    end

    def plain(line)
      line
        .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')
        .gsub(/\A\s*\#{1,6}\s+/, "")
        .gsub(/\A\s*[-*+>]\s+/, "")
        .gsub(/[*_`~|]/, " ")
    end

    def windows(tokens)
      WINDOW_SIZES.flat_map do |size|
        next [] if tokens.length < size

        (0..tokens.length - size).filter_map do |offset|
          window = tokens[offset, size]
          [ window, offset ] if acceptable?(window)
        end
      end
    end

    # A window anchored on a stopword tends to be both generic and fragile: "of campus activities is"
    # reads as noise and is likelier to butt against a line break.
    def acceptable?(window)
      downcased = window.map(&:downcase)
      return false if STOPWORDS.include?(downcased.first) || STOPWORDS.include?(downcased.last)

      downcased.any? { |token| !STOPWORDS.include?(token) && token.length > 2 }
    end

    def score(window, focus_tokens)
      downcased = window.map(&:downcase)
      overlap = downcased.count { |token| focus_tokens.include?(token) }
      substantial = downcased.count { |token| token.length >= 6 }
      (10 * overlap) + substantial + window.length
    end

    def content_tokens(text)
      text.to_s.scan(TOKEN).map(&:downcase).reject { |token| STOPWORDS.include?(token) }.to_set
    end
  end
end
