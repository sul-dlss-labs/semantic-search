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

# WORKAROUND(solr-combined-facets): delete these specs along with the workaround in
# CombinedQueryRepository once Solr can facet combined query results.
RSpec.describe CombinedQueryRepository, "faceting hybrid searches" do
  subject(:repository) { described_class.new(CatalogController.blacklight_config) }

  let(:connection) { instance_double(RSolr::Client) }
  let(:lexical) { { edismax: { query: "water" } } }
  let(:vector) { { vectorSimilarity: { f: "vector", query: "[0.1, 0.2]" } } }
  let(:solr_params) do
    Blacklight::Solr::Request.new(
      rows: 20, start: 40, sort: "score desc", fq: [ "{!term f=format_hsim}Book" ],
      facet: true, "facet.field": [ "format_hsim" ],
      combiner: true, "combiner.query": %w[lexical vector], "combiner.algorithm": "rrf",
      json: { queries: { lexical: lexical, vector: vector } }
    )
  end
  let(:requests) { {} }

  before do
    allow(repository).to receive(:connection).and_return(connection)
    allow(connection).to receive(:send_and_receive) do |path, request|
      requests[path] = JSON.parse(request[:data])
      if path == "hybrid"
        { "response" => { "numFound" => 1, "start" => 0, "docs" => [ { "id" => "abc" } ] } }
      else
        { "response" => { "numFound" => 1, "start" => 0, "docs" => [] },
          "facet_counts" => { "facet_fields" => { "format_hsim" => [ "Book", 1 ] } } }
      end
    end
  end

  it "sends the combined query without facets" do
    repository.search(params: solr_params)

    expect(requests["hybrid"]["params"]).to include("facet" => false, "combiner" => true, "rows" => 20)
    expect(requests["hybrid"]["queries"]).to be_present
  end

  it "computes facets with a select request for the union of the named queries" do
    repository.search(params: solr_params)

    expect(requests["select"]["params"]).to include(
      "facet" => true, "facet.field" => [ "format_hsim" ], "fq" => [ "{!term f=format_hsim}Book" ], "rows" => 0
    )
    expect(requests["select"]["params"]).not_to include("combiner", "combiner.query", "combiner.algorithm", "sort", "start")
    expect(requests["select"]).not_to have_key("queries")
    expect(requests["select"]["query"]).to eq("bool" => { "should" => [ lexical, vector ].map(&:deep_stringify_keys) })
  end

  it "returns the hybrid documents with the select request's facets" do
    response = repository.search(params: solr_params)

    expect(response.documents.map(&:id)).to eq [ "abc" ]
    expect(response.aggregations["format_hsim"].items.map(&:value)).to eq [ "Book" ]
  end

  it "makes a single request when the hybrid search has no facets" do
    repository.search(params: solr_params.merge(facet: false))

    expect(requests.keys).to eq [ "hybrid" ]
  end
end
