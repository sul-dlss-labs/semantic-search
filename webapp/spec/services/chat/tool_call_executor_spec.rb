# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::ToolCallExecutor do
  let(:tool_runner) { instance_double(Chat::ToolRunner, definitions: [ { type: "function" } ]) }
  let(:source_collection) { instance_double(Chat::SourceCollection, add: nil) }
  let(:result_compactor) { instance_double(Chat::ToolResultCompactor, call: "compacted result") }
  let(:executor) do
    described_class.new(
      tool_runner:,
      source_collection:,
      question: "Which frog?",
      result_compactor:
    )
  end

  def tool_call(id, name: "catalog_search_tool", arguments: { query: "frog" }.to_json)
    {
      "id" => id,
      "function" => { "name" => name, "arguments" => arguments }
    }
  end

  before do
    allow(Rails.configuration.x.chat).to receive(:max_tool_calls).and_return(10)
  end

  it "pairs the first discovery request with passage and vector searches" do
    passage_result = { text: "Passage", structured_content: { passages: [ { document_id: "abc" } ] } }
    catalog_result = { text: "Catalog", structured_content: { results: [ { title: "Frogs" } ] } }
    requested_result = { text: "Requested", structured_content: { results: [ { title: "Toads" } ] } }
    allow(tool_runner).to receive(:call).and_return(passage_result, catalog_result, requested_result)

    messages = executor.execute([ tool_call("call-1", arguments: { query: "amphibians" }.to_json) ]) { }

    expect(tool_runner).to have_received(:call).with(
      name: "search_passages",
      arguments: { "query" => "Which frog?" }
    ).ordered
    expect(tool_runner).to have_received(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "Which frog?", "search_type" => "vector", "rows" => 10 }
    ).ordered
    expect(tool_runner).to have_received(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "amphibians" }
    ).ordered
    expect(source_collection).to have_received(:add).with(
      passages: [ { document_id: "abc" } ],
      results: [ { title: "Frogs" }, { title: "Toads" } ]
    )
    expect(messages.first).to include(
      "role" => "tool",
      "tool_call_id" => "call-1",
      "content" => "compacted result"
    )
  end

  it "returns a tool response for every call when the execution limit is reached" do
    allow(Rails.configuration.x.chat).to receive(:max_tool_calls).and_return(1)
    allow(tool_runner).to receive(:call).and_return(text: "Result", structured_content: {})

    messages = executor.execute([ tool_call("call-1"), tool_call("call-2") ]) { }

    expect(messages.length).to eq(2)
    expect(messages.last).to include(
      "tool_call_id" => "call-2",
      "content" => "The tool-call limit has been reached. Use the evidence already returned."
    )
    expect(executor).to be_limit_reached
  end
end
