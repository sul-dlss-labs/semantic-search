# frozen_string_literal: true

class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior

  VECTOR_TOP_K = 250
  VECTOR_BOOST = 100.0

  # Lexical chunk matches are scored per chunk and rolled up to the parent with
  # score=max, so this is comparable with one strong chunk rather than with a
  # whole-document field. Tune against VECTOR_BOOST when balancing hybrid.
  CHUNK_BOOST = 1.0

  self.default_processor_chain += [ :add_embedding_to_query ]

  attr_reader :query_embedding

  def add_embedding_to_query(solr_parameters)
    return unless blacklight_params[:q].present?

    solr_parameters[:json] ||= { query: {} }
    solr_parameters[:json][:query][:bool] = {
      should: keyword(solr_parameters) + keyword_chunks + knn
    }
    return unless knn.present?

    solr_parameters[:json][:params] ||= {}
    solr_parameters[:json][:params][:reRankQuery] = knn
    solr_parameters[:json][:params][:reRankDocs] = 100
  end

  def keyword(solr_parameters)
    return [] if blacklight_params[:search_type] == "vector"

    must_queries = solr_parameters.dig(:json, :query, :bool, :must)
    return Array.wrap(must_queries) if must_queries.present? # advance search is enabled

    return [] unless solr_parameters[:q].present?

    [ { edismax: { query: solr_parameters[:q] } } ]
  end

  # Lexical search over the extracted chunk text. Mirrors #knn: the match is
  # made against child documents and rolled up to the parent with score=max, so
  # a phrase occurring in one chunk of a 1,000-chunk volume is not diluted by
  # document length.
  def keyword_chunks
    return [] if blacklight_params[:search_type] == "vector"
    return [] unless blacklight_params[:q].present?

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
                  query: blacklight_params[:q],
                  qf: "chunk_text_tesi"
                }
              }
            }
          }
        }
      }
    ]
  end

  def knn
    return [] if blacklight_params[:search_type] == "keyword"
    @knn ||= [
      {
        boost: {
          b: VECTOR_BOOST,
          query: {
            parent: {
              which: "doc_type_ssi:parent",
              # Without this the parent parser defaults to score=none and every match scores 0.
              score: "max",
              query: {
                knn: {
                  f: "vector",
                  # note that topK is referring to the number of child documents.
                  # The index averages ~29 chunks per parent.
                  # Increasing topK mitigates the long-document bias, but setting top-K too high can slow down the query.
                  # We want this high enough such that "the baseball player who threw the first pitch in Florida Marlins organization history"
                  # returns both zv638jb7154 and bb051hp9404
                  topK: VECTOR_TOP_K,
                  query:  "[#{retrieve_embedding(blacklight_params[:q]).join(', ')}]"
                }
              }
            }
          }
        }
      }
    ]
  end

  def retrieve_embedding(input)
    @query_embedding = Rails.cache.fetch("embedding/#{input}") do
      client = GeminiEmbedding.new
      client.embedding(input: [ input ],
                       instruction: GeminiEmbedding::DEFAULT_QUERY_INSTRUCTION).first
    end
  end
end
