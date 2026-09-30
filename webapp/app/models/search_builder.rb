# frozen_string_literal: true

class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior

  # Solr normalizes cosine similarity scores to the range [0, 1]. The retrieval
  # evaluation baseline has relevant results down to 0.84, so this leaves some
  # recall headroom while excluding weak semantic matches.
  VECTOR_MIN_RETURN = 0.8
  VECTOR_BOOST = 100.0

  # Lexical chunk matches are scored per chunk and rolled up to the parent with
  # score=max, so this is comparable with one strong chunk rather than with a
  # whole-document field within the lexical ranking.
  CHUNK_BOOST = 1.0

  # Number of top-scoring documents from the main query to rescore with the vector query.
  RERANK_DOCS = 100

  self.default_processor_chain += [ :add_embedding_to_query ]

  attr_reader :query_embedding

  def add_embedding_to_query(solr_parameters)
    unless search_state.params[:q].present?
      # q.alt only applies to DisMax parsers. Keep the initial browse request
      # explicit so Solr returns documents and their facet counts.
      solr_parameters[:q] = "*:*" if solr_parameters[:q].blank?
      return
    end

    if search_state.params[:search_type] == "hybrid"
      lexical_queries = keyword(solr_parameters) + keyword_chunks
      # The named JSON queries specify their own parsers. A request-level q
      # interferes with their interpretation by Solr's combined handler.
      solr_parameters.delete(:q)
      solr_parameters[:json] = (solr_parameters[:json] || {}).except(:query).merge(queries: {
        lexical: { bool: { should: lexical_queries } },
        vector: vector_similarity.first
      })
      solr_parameters[:combiner] = true
      solr_parameters[:"combiner.query"] = %w[lexical vector]
      solr_parameters[:"combiner.algorithm"] = "rrf"
      return
    end

    if search_state.params[:search_type] == "vector"
      solr_parameters.delete(:q)
    else
      solr_parameters[:defType] = "edismax"
    end
    solr_parameters[:json] ||= { query: {} }
    solr_parameters[:json][:query][:bool] = {
      should: keyword(solr_parameters) + keyword_chunks + vector_similarity
    }
    return unless vector_similarity.present?

    add_vector_rerank(solr_parameters)
  end

  # The rerank parser is only applied via the top-level rq param and its reRankQuery must be
  # a query string, so this restates the vector clause in local-params syntax. These are
  # plain Solr params (not json.params) so Blacklight merges them into the single "params"
  # block of the JSON request.
  def add_vector_rerank(solr_parameters)
    solr_parameters[:rq] = "{!rerank reRankQuery=$rqq reRankDocs=#{RERANK_DOCS} reRankWeight=#{VECTOR_BOOST}}"
    solr_parameters[:rqq] = "{!parent which=doc_type_ssi:parent score=max v=$rqq_vector}"
    solr_parameters[:rqq_vector] = "{!vectorSimilarity f=vector minReturn=#{VECTOR_MIN_RETURN}}#{embedding_vector}"
  end

  def keyword(solr_parameters)
    return [] if search_state.params[:search_type] == "vector"

    must_queries = solr_parameters.dig(:json, :query, :bool, :must)
    return Array.wrap(must_queries) if must_queries.present? # advance search is enabled

    return [] unless solr_parameters[:q].present?

    [ { edismax: { query: solr_parameters[:q] } } ]
  end

  # Lexical search over the extracted chunk text. Mirrors #vector_similarity: the match is
  # made against child documents and rolled up to the parent with score=max, so
  # a phrase occurring in one chunk of a 1,000-chunk volume is not diluted by
  # document length.
  def keyword_chunks
    return [] if search_state.params[:search_type] == "vector"
    return [] unless search_state.params[:q].present?

    [
      {
        boost: {
          b: CHUNK_BOOST,
          query: {
            parent: {
              which: "doc_type_ssi:parent",
              # Without this the parent parser defaults to score=none and every match scores 0.
              score: "max",
              query: {
                edismax: {
                  query: search_state.params[:q],
                  qf: "chunk_text_tesi"
                }
              }
            }
          }
        }
      }
    ]
  end

  def vector_similarity
    return [] if search_state.params[:search_type] == "keyword"
    @vector_similarity ||= [
      {
        boost: {
          b: VECTOR_BOOST,
          query: {
            parent: {
              which: "doc_type_ssi:parent",
              # Without this the parent parser defaults to score=none and every match scores 0.
              score: "max",
              query: {
                vectorSimilarity: {
                  f: "vector",
                  # Apply the threshold to child chunks before rolling their best score up
                  # to the parent. Unlike topK, this does not make documents compete for a
                  # fixed global child-chunk budget.
                  minReturn: VECTOR_MIN_RETURN,
                  query: embedding_vector
                }
              }
            }
          }
        }
      }
    ]
  end

  def embedding_vector
    "[#{retrieve_embedding(search_state.params[:q]).join(', ')}]"
  end

  def retrieve_embedding(input)
    @query_embedding = GeminiEmbedding.query_embedding(input)
  end
end
