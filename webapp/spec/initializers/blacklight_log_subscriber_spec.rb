require "rails_helper"

RSpec.describe TruncateSolrLogValues do
  subject(:subscriber) { Blacklight::LogSubscriber.new }

  let(:output) { StringIO.new }
  let(:embedding) { "[#{Array.new(768) { 0.0123456789 }.join(', ')}]" }
  let(:params) do
    { json: { query: { knn: { f: "vector", topK: 20, preFilter: [ "doc_type_ssi:child" ], query: embedding } } } }
  end
  let(:event) do
    ActiveSupport::Notifications::Event.new("solr_request.blacklight", Time.zone.now, Time.zone.now, "id",
                                            method: :post, path: "select", params:)
  end

  around do |example|
    original = Blacklight.logger
    Blacklight.logger = ActiveSupport::Logger.new(output)
    example.run
    Blacklight.logger = original
  end

  it "replaces the embedding with a placeholder but keeps the rest of the query" do
    subscriber.solr_request(event)

    expect(output.string).to include("OMITTED (#{embedding.length} characters)")
    expect(output.string).not_to include("0.0123456789")
    expect(output.string).to include(%(f: "vector"), "20", %("doc_type_ssi:child"))
  end
end
