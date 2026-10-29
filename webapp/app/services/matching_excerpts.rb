# frozen_string_literal: true

# Finds the text chunks that caused each search result to match, so the results page can show
# the user *why* a document came back.
#
# Documents are indexed as nested Solr blocks: a `doc_type_ssi:parent` record holding the
# metadata, plus one `doc_type_ssi:child` record per ~1,200 character chunk. SearchBuilder
# matches those children and rolls the best score up to the parent with {!parent score=max},
# which means the winning chunk is discarded by the time Blacklight has a result set. This
# service goes back for it with a single grouped query over the current page's documents.
#
# Grouping on _root_ (rather than over-fetching and grouping in Ruby) is what guarantees every
# result gets its own top chunks: a 37-chunk volume cannot crowd out a 5-chunk one. It also
# recovers the parent id via `groupValue`, which matters because _root_ is indexed but not
# stored and so cannot be requested as a field.
class MatchingExcerpts
  EXCERPTS_PER_DOCUMENT = 3
  FRAGMENT_CHARACTERS = 240
  MAX_EXCERPT_CHARACTERS = 400

  # Chunk 0 of every document is a synthetic chunk of concatenated metadata. It scores highly in
  # hybrid search and would otherwise be the first "excerpt" on nearly every result.
  METADATA_FILENAME = "_metadata_"

  GROUP_FIELD = "_root_"
  HIGHLIGHT_FIELD = "chunk_text_tesi"
  TIME_ALLOWED_MS = 2_000

  # Score each half of the query separately as a pseudo-field
  VECTOR_SCORE_FIELD = "vector_score"
  KEYWORD_MATCH_FIELD = "keyword_match"

  # How many of the query's subject words a chunk must contain to count as a keyword match, which
  # is also what it takes for the chunk to be highlighted at all: half, rounded down, and never
  # fewer than one. A chunk that matched a six-word query by meaning but shares only two of its
  # words with it ("undergraduate", "days") is neither.
  # See https://solr.apache.org/guide/solr/latest/query-guide/dismax-query-parser.html#mm-minimum-should-match-parameter
  KEYWORD_MIN_MATCH = "50%"

  # @param documents [Array<SolrDocument>] the current page of results
  # @param query [String, nil] the user's query
  # @param search_type [String, nil] "keyword", "vector", or nil for hybrid
  # @param embedding [Array<Float>, nil] SearchBuilder#query_embedding; nil in keyword mode
  # @param repository [Blacklight::AbstractRepository] injected so specs can run without Solr
  def initialize(documents:, query:, search_type: nil, embedding: nil,
                 repository: CatalogController.blacklight_config.repository)
    @documents = Array(documents)
    @query = query
    @search_type = search_type
    @embedding = embedding
    @repository = repository
  end

  # @return [Hash{String => Array<Hash>}] document id => excerpts, at most EXCERPTS_PER_DOCUMENT
  def call
    return {} if @query.blank?

    excerpts = child_document_excerpts
    return excerpts if parent_ids.empty? || should_clauses.empty?

    excerpts.merge(grouped_excerpts)
  rescue StandardError => e
    # Excerpts decorate the results page; they must never take it down.
    Rails.logger.warn("Matching excerpts unavailable: #{e.class}: #{e.message}")
    excerpts || {}
  end

  private

  def grouped_excerpts
    response = @repository.search(params: solr_params)
    grouped = response.grouped? && response.group(GROUP_FIELD)
    return {} unless grouped

    highlighting = response["highlighting"] || {}

    grouped.groups.each_with_object({}) do |group, excerpts|
      excerpts[group.key] = group.docs.map { |chunk| excerpt_for(chunk, highlighting) }
    end
  end

  # Child chunks are currently surfaced as results in their own right. They already carry their
  # text, so they need no extra query -- and their own id must stay out of the _root_ filter,
  # which only ever holds parent ids.
  def child_document_excerpts
    child_documents.each_with_object({}) do |document, excerpts|
      text = document[HIGHLIGHT_FIELD]
      next if text.blank?

      excerpts[document.id] = [ {
        chunk_id: document.id,
        snippet: bounded(ERB::Util.html_escape(text).to_s),
        highlighted: false,
        filename: document["filename_ss"],
        page: document["page_ss"],
        chunk_index: document["chunk_index_i"],
        score: document["score"],
        public: document["public_bsi"]
      }.compact ]
    end
  end

  def excerpt_for(chunk, highlighting)
    match = match_type(chunk)
    snippet = bounded(sanitized(highlighting.dig(chunk.id, HIGHLIGHT_FIELD)&.first.to_s))

    # Remove highlighting on chunks that matched only via vector search, since
    # the highlighting is misleading: we didn't match on specific words
    snippet = snippet.gsub(%r{</?mark>}, "") if match == :semantic

    {
      chunk_id: chunk.id,
      snippet: snippet,
      highlighted: snippet.include?("<mark>"),
      match: match,
      filename: chunk["filename_ss"],
      page: chunk["page_ss"],
      chunk_index: chunk["chunk_index_i"],
      score: chunk["score"],
      # Access is indexed per chunk, not on the parent, so callers decide from this who may see it.
      public: chunk["public_bsi"]
    }.compact
  end

  # @return [Symbol, nil] why the chunk matched: :keyword, :semantic, or :both
  def match_type(chunk)
    return if signal_queries.empty?

    semantic = chunk[VECTOR_SCORE_FIELD].to_f.positive?
    keyword = chunk[KEYWORD_MATCH_FIELD].to_f.positive?
    return :keyword unless semantic

    keyword ? :both : :semantic
  end

  # Solr escapes the source text and inserts only <mark> (hl.encoder=html), but the text is
  # untrusted OCR and that guarantee rests on one request parameter. If anything else shows up,
  # drop all markup rather than pass it along. The view sanitizes again before rendering.
  def sanitized(snippet)
    return snippet unless snippet.gsub(%r{</?mark>}, "").match?(/<[^>]+>/)

    strip_tags(snippet)
  end

  # Solr centres the fragment on the match but rounds out to a sentence boundary, which
  # regularly overshoots. Truncate on visible text and step over the <mark> tags, so the
  # highlighting the user came for survives the trim.
  def bounded(snippet)
    return snippet if visible_length(snippet) <= MAX_EXCERPT_CHARACTERS

    remaining = MAX_EXCERPT_CHARACTERS
    open = false
    kept = +""

    # Stop at the limit rather than skip the rest of the text: carrying on would keep the tags of
    # every later match, rendering each as an empty highlight.
    snippet.split(%r{(</?mark>)}).each do |part|
      break if remaining.zero?

      case part
      when "<mark>" then open = true
      when "</mark>" then open = false
      else
        part = truncate_text(part, remaining)
        remaining -= visible_length(part)
      end
      kept << part
    end

    kept << "</mark>" if open
    "#{kept}…"
  end

  def truncate_text(text, limit)
    return text if visible_length(text) <= limit

    # Entities count as one visible character, so cut on the entity-aware scan and never leave
    # a half-written "&amp;" behind.
    text.scan(/&[a-zA-Z#0-9]+;|./m).first(limit).join
  end

  def visible_length(text)
    text.gsub(%r{</?mark>}, "").scan(/&[a-zA-Z#0-9]+;|./m).length
  end

  def strip_tags(snippet)
    ActionController::Base.helpers.strip_tags(snippet)
  end

  def child_documents
    @child_documents ||= @documents.select { |document| document["doc_type_ssi"] == "child" }
  end

  # Ids containing the {!terms} separator would silently split into bogus terms.
  def parent_ids
    @parent_ids ||= (@documents - child_documents).filter_map(&:id).uniq.reject { |id| id.include?(",") }
  end

  def solr_params
    {
      facet: false,
      "group" => true,
      "group.field" => GROUP_FIELD,
      "group.limit" => EXCERPTS_PER_DOCUMENT,
      # When grouping, `rows` counts groups rather than documents.
      "rows" => parent_ids.length,
      "timeAllowed" => TIME_ALLOWED_MS,
      "hl" => true,
      "hl.fl" => HIGHLIGHT_FIELD,
      # Required: the highlighter does not see the query when it is expressed in the JSON DSL,
      # and silently returns empty highlights without this. edismax is lenient, so malformed user
      # input cannot turn into a 400. The user's words are passed by reference so they can never
      # rewrite the local params; filler words are left out so that only the subject of a
      # question is highlighted.
      "hl.q" => keyword_match_query,
      "hlq" => HighlightQuery.new(@query).call,
      "hl.snippets" => 1,
      "hl.fragsize" => FRAGMENT_CHARACTERS,
      "hl.encoder" => "html",
      "hl.tag.pre" => "<mark>",
      "hl.tag.post" => "</mark>",
      # Gives semantically-matched chunks a bounded leading snippet when no term matches.
      "hl.defaultSummary" => true,
      json: {
        query: {
          bool: {
            # Alongside a filter, bare should clauses become optional and every chunk in the
            # document matches, padding each group with unrelated zero-scored chunks. Nesting them
            # in must requires a chunk to match at least one.
            must: [ { bool: { should: should_clauses } } ],
            filter: [ "doc_type_ssi:child", terms_filter ],
            # A bare "-field:value" string in `filter` matches nothing; must_not is required.
            must_not: [ "filename_ss:#{METADATA_FILENAME}" ]
          }
        },
        # chunk_text_tesi is deliberately omitted: hl.defaultSummary always supplies a snippet,
        # so fetching the full chunk would quadruple the response for nothing.
        fields: %w[id chunk_index_i filename_ss page_ss score public_bsi] + signal_fields
      }
    }.merge(signal_queries)
  end

  # Queries scoring each half of a hybrid or vector search on its own, for #signal_fields; see
  # #match_type. Empty in a keyword search, which has only the one half.
  def signal_queries
    @signal_queries ||= if vector_query
      similarity = vector_query[:vectorSimilarity]
      filters = similarity[:preFilter].each_with_index.to_h { |filter, i| [ "excerpt_filter_#{i}", filter ] }
      filter_refs = filters.keys.map { |key| "preFilter=$#{key}" }.join(" ")

      {
        "excerpt_vector" => "{!vectorSimilarity f=#{similarity[:f]} minReturn=#{similarity[:minReturn]} " \
                            "#{filter_refs}}#{similarity[:query]}",
        "excerpt_keyword" => keyword_match_query
      }.merge(filters)
    else
      {}
    end
  end

  # Matches a chunk containing at least KEYWORD_MIN_MATCH of the query's subject words (hlq).
  # The same query decides both what is highlighted and what counts as a keyword match, so no
  # chunk is highlighted without counting as one.
  def keyword_match_query
    "{!edismax qf=#{HIGHLIGHT_FIELD} mm='#{KEYWORD_MIN_MATCH}' v=$hlq}"
  end

  # query() scores a chunk against one of #signal_queries, falling back to 0 where it does not
  # match.
  def signal_fields
    return [] if signal_queries.empty?

    [ "#{VECTOR_SCORE_FIELD}:query($excerpt_vector,0)", "#{KEYWORD_MATCH_FIELD}:query($excerpt_keyword,0)" ]
  end

  # Mirrors SearchBuilder's clauses, reusing its constants so excerpt ranking cannot drift away
  # from the result ranking it is supposed to explain.
  def should_clauses
    @should_clauses ||= [ keyword_clause, vector_clause ].compact
  end

  def keyword_clause
    return if @search_type == "vector"

    { edismax: { query: @query, qf: HIGHLIGHT_FIELD } }
  end

  def vector_clause
    return unless vector_query

    { boost: { b: SearchBuilder::VECTOR_BOOST, query: vector_query } }
  end

  def vector_query
    return if @search_type == "keyword" || !usable_embedding?

    @vector_query ||= {
      vectorSimilarity: {
        f: "vector",
        minReturn: SearchBuilder::VECTOR_MIN_RETURN,
        # A nested vector query does not inherit the enclosing bool's filters.
        preFilter: [ "doc_type_ssi:child", terms_filter, "-filename_ss:#{METADATA_FILENAME}" ],
        query: "[#{@embedding.join(', ')}]"
      }
    }
  end

  # A wrong-length vector is a Solr 400, so check before sending one.
  def usable_embedding?
    @embedding.present? && @embedding.length == GeminiEmbedding::DIMENSIONS
  end

  # The terms parser looks terms up directly, so values must NOT be escaped.
  def terms_filter
    "{!terms f=#{GROUP_FIELD}}#{parent_ids.join(',')}"
  end
end
