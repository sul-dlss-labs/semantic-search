# frozen_string_literal: true

class SearchBuilder < Blacklight::SearchBuilder
  include Blacklight::Solr::SearchBuilderBehavior

  self.default_processor_chain += [ :add_embedding_to_query ]

  def add_embedding_to_query(solr_parameters)
    return unless blacklight_params[:q].present?

    solr_parameters[:json][:query][:bool] = {
      should: keyword(solr_parameters) + knn
    }
    return unless knn.present?

    solr_parameters[:json][:params] ||= {}
    solr_parameters[:json][:params][:reRankQuery] = knn
    solr_parameters[:json][:params][:reRankDocs] = 100
  end

  def keyword(solr_parameters)
    return [] if blacklight_params[:search_type] == "vector"
    solr_parameters.dig(:json, :query, :bool, :must)
  end

  def knn
    return [] if blacklight_params[:search_type] == "keyword"
    @knn ||= [
      parent: {
        which: "doc_type_ssi:parent",
        query: {
          knn: {
            f: "vector",
            topK: 10,
            query:  "[#{retrieve_embedding(blacklight_params[:q]).join(', ')}]"
          }
        },
        boost: 100.0
      }
    ]
  end

  def retrieve_embedding(input)
    Rails.cache.fetch("embedding/#{input}") do
      client = GeminiEmbedding.new
      client.embedding(input: [ input ],
                       instruction: GeminiEmbedding::DEFAULT_QUERY_INSTRUCTION).first
    end
  end
end
