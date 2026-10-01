# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::DeterministicDiscovery do
  subject(:discovery) { described_class.new(tool_runner:) }

  let(:tool_runner) { instance_double(Chat::ToolRunner) }
  let(:query) { "Who died after falling while climbing a mountain in Iran?" }
  let(:catalog_arguments) { { "query" => query, "search_type" => "vector", "rows" => 10 } }

  it "searches passages within the five highest-ranked catalog documents and prioritizes them" do
    document_ids = (1..6).map { |index| "document-#{index}" }
    global_passage = { rank: 1, text: "An unrelated death", document_id: "unrelated" }
    constrained_passage = { rank: 1, text: "Kathleen Namphy descended Mount Damavand", document_id: "document-1" }
    catalog_results = document_ids.map { |id| { id:, title: id, url: "/catalog/#{id}" } }

    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => query }
    ).and_return(text: "Global", structured_content: { passages: [ global_passage ] })
    allow(tool_runner).to receive(:call).with(
      name: "catalog_search_tool",
      arguments: catalog_arguments
    ).and_return(text: "Catalog", structured_content: { results: catalog_results })
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => query, "document_ids" => document_ids.first(5) }
    ).and_return(text: "Constrained", structured_content: { passages: [ constrained_passage ] })

    result = discovery.call(
      query:,
      requested_name: "catalog_search_tool",
      requested_arguments: catalog_arguments
    )

    expect(result).to include(error: false)
    expect(result.dig(:structured_content, :passages)).to eq([ constrained_passage, global_passage ])
    expect(result.dig(:structured_content, :results)).to eq(catalog_results)
    expect(tool_runner).to have_received(:call).exactly(3).times
  end

  it "combines the remaining results when a search fails" do
    error = { text: "Passage search failed", structured_content: { error: "failed" }, error: true }
    catalog_result = { id: "document-1", title: "Document 1", url: "/catalog/document-1" }
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => query }
    ).and_return(error)
    allow(tool_runner).to receive(:call).with(
      name: "catalog_search_tool",
      arguments: catalog_arguments
    ).and_return(text: "Catalog", structured_content: { results: [ catalog_result ] })
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => query, "document_ids" => [ "document-1" ] }
    ).and_return(error)

    result = discovery.call(
      query:,
      requested_name: "catalog_search_tool",
      requested_arguments: catalog_arguments
    )

    expect(result).to include(error: false)
    expect(result.dig(:structured_content, :results)).to eq([ catalog_result ])
    expect(result.dig(:structured_content, :passages)).to be_empty
  end

  describe ".handles?" do
    it "recognizes only discovery tools" do
      expect(described_class).to be_handles("catalog_search_tool")
      expect(described_class).to be_handles("search_passages")
      expect(described_class).not_to be_handles("get_document_chunks")
    end
  end

  describe "carried search filters" do
    let(:filters) { { "collection" => "Stanford Oral History Project" } }

    def stub_searches(expected_catalog_arguments)
      allow(tool_runner).to receive(:call).and_return(text: "", structured_content: {})
      allow(tool_runner).to receive(:call).with(
        name: "catalog_search_tool", arguments: expected_catalog_arguments
      ).and_return(text: "Catalog", structured_content: { results: [] })
    end

    it "applies the carried filters when the model requested none" do
      expected = catalog_arguments.merge("filters" => filters)
      stub_searches(expected)

      discovery.call(query:, requested_name: "search_passages", requested_arguments: { "query" => query },
                     context_filters: filters)

      expect(tool_runner).to have_received(:call).with(name: "catalog_search_tool", arguments: expected)
    end

    it "lets the model's own filters win over the carried ones" do
      requested = { "query" => query, "filters" => { "topic" => "Music" } }
      expected = catalog_arguments.merge("filters" => { "topic" => "Music" })
      stub_searches(expected)

      discovery.call(query:, requested_name: "catalog_search_tool", requested_arguments: requested,
                     context_filters: filters)

      expect(tool_runner).to have_received(:call).with(name: "catalog_search_tool", arguments: expected)
    end

    it "leaves the fan-out unfiltered when there is no carried search" do
      stub_searches(catalog_arguments)

      discovery.call(query:, requested_name: "search_passages", requested_arguments: { "query" => query })

      expect(tool_runner).to have_received(:call).with(name: "catalog_search_tool", arguments: catalog_arguments)
    end
  end
end
