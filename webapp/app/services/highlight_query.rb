# frozen_string_literal: true

# Reduces a search to the terms worth highlighting in a matching excerpt.
#
# Users ask questions: "Is there anything about "Phil Knight" in the repository?". Solr's
# stopwords drop "is", "there", "in" and "the", but "anything", "about" and "repository" survive
# and get highlighted wherever they occur, burying the words the user actually came for.
#
# Quoted phrases are kept whole, since quoting is an explicit statement of what matters. The
# remaining words are kept unless they are conversational filler. If nothing is left (a query of
# nothing but filler), the original query is used so there is still something to highlight.
#
# This only shapes highlighting; ranking still sees the full query.
class HighlightQuery
  # Words that frame a question or request rather than describe its subject, plus Solr's English
  # stopwords so none are left dangling. Boolean operators are deliberately absent, so "AND",
  # "OR" and "NOT" keep their meaning.
  FILLER_WORDS = %w[
    a about an any anything are as at be but by can could did do does documents everything files
    find for give had has have how i if in info information into is it items know list look
    looking materials me mention mentioned mentions my of on please regarding related repository
    say says show some something such tell that the their then there these they this to was we
    were what what's when where which who why will with would you
  ].to_set.freeze

  # Trailing punctuation would otherwise reach Solr attached to a kept word, where "?" is a
  # wildcard.
  TRAILING_PUNCTUATION = /[?!.,;:]+\z/

  def initialize(query)
    @query = query.to_s.strip
  end

  # @return [String] the query to highlight with; never blank unless the query was
  def call
    phrases = @query.scan(CatalogSearchClassifier::QUOTED_PHRASE).map { |phrase| phrase.tr("“”", '""') }
    words = @query.gsub(CatalogSearchClassifier::QUOTED_PHRASE, " ").split.filter_map { |token| subject_word(token) }

    (phrases + words).join(" ").presence || @query
  end

  private

  def subject_word(token)
    word = token.sub(TRAILING_PUNCTUATION, "")
    word unless word.empty? || FILLER_WORDS.include?(word.downcase.tr("’", "'"))
  end
end
