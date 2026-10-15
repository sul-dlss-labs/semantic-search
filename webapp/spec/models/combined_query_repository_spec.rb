require "rails_helper"

RSpec.describe CombinedQueryRepository do
  subject(:repository) { described_class.allocate }

  before do
    allow(repository).to receive(:blacklight_config).and_return(CatalogController.blacklight_config)
  end

  it "uses the combined query handler for RRF requests" do
    expect(repository.send(:default_search_path, { json: { queries: { lexical: {}, vector: {} } } })).to eq("hybrid")
  end

  it "keeps ordinary JSON queries on Blacklight's JSON path" do
    expect(repository.send(:default_search_path, { json: { query: { knn: {} } } })).to eq("select")
  end
end
