# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::ToolRunner do
  subject(:runner) { described_class.new }

  it "publishes only the application's MCP tools to the model" do
    expect(runner.definitions.pluck(:function).pluck(:name)).to eq(
      %w[catalog_search_tool get_document_chunks search_passages]
    )
    expect(runner.definitions).to all(include(type: "function"))
  end

  it "projects MCP schemas onto a provider-compatible function-calling subset" do
    serialized_definitions = runner.definitions.to_json

    expect(serialized_definitions).not_to include("additionalProperties", "uniqueItems", "default")
    expect(runner.definitions.first.dig(:function, :parameters)).to include(
      type: "object",
      required: %w[query search_type]
    )
    expect(runner.definitions.first.dig(:function, :parameters, :properties)).to include(:query, :search_type)
    expect(runner.definitions.first.dig(:function, :parameters, :properties, :query, :description))
      .to include("question verbatim")
    passage_tool = runner.definitions.find { |definition| definition.dig(:function, :name) == "search_passages" }
    expect(passage_tool.dig(:function, :parameters, :properties, :query, :description)).to include("question verbatim")
  end

  it "validates arguments and executes an allowlisted handler" do
    result = {
      text: "Found frogs",
      structured_content: { results: [ { title: "Frogs", url: "/catalog/1" } ] }
    }
    allow(SemanticSearchMcp::CatalogSearch).to receive(:search).with(
      controller: nil,
      query: "frogs",
      search_type: "vector",
      rows: 2
    ).and_return(result)

    expect(runner.call(name: "catalog_search_tool", arguments: { "query" => "frogs", "rows" => 2 })).to eq(result)
  end

  it "preserves an explicit non-vector catalog search type" do
    allow(SemanticSearchMcp::CatalogSearch).to receive(:search).with(
      controller: nil,
      query: "Exact Title",
      search_type: "keyword"
    ).and_return(text: "Found title", structured_content: { results: [] })

    runner.call(name: "catalog_search_tool", arguments: { "query" => "Exact Title", "search_type" => "keyword" })

    expect(SemanticSearchMcp::CatalogSearch).to have_received(:search).with(
      controller: nil,
      query: "Exact Title",
      search_type: "keyword"
    )
  end

  it "instruments the tool name and inputs before execution" do
    allow(SemanticSearchMcp::CatalogSearch).to receive(:search).and_return(
      text: "No results",
      structured_content: { results: [] }
    )
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(
      SemanticSearchMcp::Tools::START_INSTRUMENTATION_EVENT
    ) { |event| events << event }

    runner.call(name: "catalog_search_tool", arguments: { "query" => "frogs", "search_type" => "vector" })

    expect(events.map(&:payload)).to contain_exactly(
      include(
        tool_name: "catalog_search_tool",
        input: { "query" => "frogs", "search_type" => "vector" }
      )
    )
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "rejects arguments outside the MCP schema" do
    result = runner.call(name: "catalog_search_tool", arguments: { "query" => "frogs", "unexpected" => true })

    expect(result).to include(error: true)
    expect(result[:text]).to include("disallowed additional property")
  end

  it "rejects tools outside the local allowlist" do
    result = runner.call(name: "run_shell", arguments: {})

    expect(result).to include(error: true, text: "Tool not found: run_shell")
  end
end
