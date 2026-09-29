# frozen_string_literal: true

# Chooses a retrieval strategy for catalog searches submitted through the UI.
# Ambiguous queries use hybrid search so neither lexical nor semantic matches
# are discarded based on a weak guess about the user's intent.
class CatalogSearchClassifier
  QUESTION_START = /\A(?:who|what|when|where|why|how|which|is|are|was|were|do|does|did|can|could|would|should)\b/i
  QUOTED_PHRASE = /["“][^"”]+["”]/
  FIELD_QUERY = /\b(?:id|druid|doi|isbn|issn|title|author):\S/i
  IDENTIFIER = /\A(?:[a-z]{2}\d{3}[a-z]{2}\d{4}|10\.\d{4,9}\/\S+)\z/i
  SMALL_WORDS = %w[a an and as at by for from in of on or the to with].freeze

  def initialize(query)
    @query = query.to_s.strip
    @words = @query.scan(/[[:alpha:]][[:alpha:]'’-]*/)
  end

  def call
    question = @query.match?(QUESTION_START) || @query.end_with?("?")
    exact = @query.match?(QUOTED_PHRASE) || @query.match?(FIELD_QUERY) || @query.match?(IDENTIFIER)
    named = @words.each_cons(2).any? do |first, second|
      [ first, second ].all? { |word| word.match?(/\A\p{Lu}/) && !SMALL_WORDS.include?(word.downcase) }
    end

    if question
      return (exact || named) ? "hybrid" : "vector"
    end
    return "keyword" if exact || title_like?
    return "hybrid" if named
    return "vector" if @words.length >= 8

    "hybrid"
  end

  private

  def title_like?
    return false unless (2..7).cover?(@words.length)

    meaningful_words = @words.reject { |word| SMALL_WORDS.include?(word.downcase) }
    meaningful_words.length >= 2 && meaningful_words.all? { |word| word.match?(/\A\p{Lu}/) }
  end
end
