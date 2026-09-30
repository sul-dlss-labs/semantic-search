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
        score: document["score"]
      }.compact ]
    end
  end

  def excerpt_for(chunk, highlighting)
    snippet = bounded(sanitized(highlighting.dig(chunk.id, HIGHLIGHT_FIELD)&.first.to_s))

    {
      chunk_id: chunk.id,
      snippet: snippet,
      highlighted: snippet.include?("<mark>"),
      filename: chunk["filename_ss"],
      page: chunk["page_ss"],
      chunk_index: chunk["chunk_index_i"],
      score: chunk["score"]
    }.compact
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

    kept = snippet.split(%r{(</?mark>)}).map do |part|
      case part
      when "<mark>" then open = true
      when "</mark>" then open = false
      else
        next "" if remaining.zero?

        part = truncate_text(part, remaining)
        remaining -= visible_length(part)
      end
      part
    end.join

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
      # and silently returns empty highlights without this.
      "hl.q" => @query,
      # edismax is lenient, so malformed user input cannot turn into a 400.
      "hl.qparser" => "edismax",
      "hl.qf" => HIGHLIGHT_FIELD,
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
            should: should_clauses,
            filter: [ "doc_type_ssi:child", terms_filter ],
            # A bare "-field:value" string in `filter` matches nothing; must_not is required.
            must_not: [ "filename_ss:#{METADATA_FILENAME}" ]
          }
        },
        # chunk_text_tesi is deliberately omitted: hl.defaultSummary always supplies a snippet,
        # so fetching the full chunk would quadruple the response for nothing.
        fields: %w[id chunk_index_i filename_ss page_ss score]
      }
    }
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
    return if @search_type == "keyword" || !usable_embedding?

    {
      boost: {
        b: SearchBuilder::VECTOR_BOOST,
        query: {
          vectorSimilarity: {
            f: "vector",
            minReturn: SearchBuilder::VECTOR_MIN_RETURN,
            # A nested vector query does not inherit the enclosing bool's filters.
            preFilter: [ "doc_type_ssi:child", terms_filter, "-filename_ss:#{METADATA_FILENAME}" ],
            query: "[#{@embedding.join(', ')}]"
          }
        }
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
