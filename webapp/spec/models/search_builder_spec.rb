require "rails_helper"

RSpec.describe SearchBuilder do
  subject(:builder) { described_class.allocate }

  before do
    allow(builder).to receive(:blacklight_params).and_return({ q: "first Marlins pitch", search_type: "vector" })
    allow(builder).to receive(:retrieve_embedding).with("first Marlins pitch").and_return([ 0.1, 0.2 ])
  end

  describe "#vector_similarity" do
    it "selects child chunks using a minimum similarity threshold" do
      vector_query = builder.vector_similarity.dig(0, :boost, :query, :parent, :query, :vectorSimilarity)

      expect(vector_query).to eq(
        f: "vector",
        minReturn: described_class::VECTOR_MIN_RETURN,
        query: "[0.1, 0.2]"
      )
      expect(vector_query).not_to have_key(:topK)
    end
  end

  describe "#add_embedding_to_query" do
    it "uses the threshold query for retrieval and reranking" do
      solr_parameters = {}

      builder.add_embedding_to_query(solr_parameters)

      vector_clause = builder.vector_similarity
      expect(solr_parameters.dig(:json, :query, :bool, :should)).to eq(vector_clause)
      expect(solr_parameters.dig(:json, :params)).to eq(
        reRankQuery: vector_clause,
        reRankDocs: 100
      )
    end
  end
end
