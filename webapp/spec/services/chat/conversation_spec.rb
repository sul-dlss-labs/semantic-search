# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::Conversation do
  let(:client) { FakeClient.new }
  let(:tool_runner) { instance_double(Chat::ToolRunner, definitions: [ { type: "function" } ]) }

  class FakeClient
    attr_reader :requests

    def initialize
      @responses = []
      @requests = []
    end

    def enqueue(content: nil, tool_calls: [], deltas: [], finish_reason: "stop")
      @responses << { content:, tool_calls:, deltas:, finish_reason: }
    end

    def stream_completion(messages:, tools:)
      @requests << { messages:, tools: }
      response = @responses.shift
      response.fetch(:deltas).each { |delta| yield delta }
      message = { "role" => "assistant", "content" => response[:content] }
      message["tool_calls"] = response[:tool_calls] if response[:tool_calls].any?
      Chat::LiteLlmClient::Completion.new(
        message:,
        tool_calls: response[:tool_calls],
        finish_reason: response[:finish_reason]
      )
    end
  end

  def tool_call(id, query)
    {
      "id" => id,
      "type" => "function",
      "function" => { "name" => "catalog_search_tool", "arguments" => { query: }.to_json }
    }
  end

  it "can make multiple local MCP calls before streaming a sourced answer" do
    client.enqueue(tool_calls: [ tool_call("call-1", "frogs"), tool_call("call-2", "toads") ])
    client.enqueue(content: "The corpus discusses frogs and toads.", deltas: [ "The corpus ", "discusses frogs and toads." ])
    allow(tool_runner).to receive(:call).with(name: "catalog_search_tool", arguments: { "query" => "frogs" }).and_return(
      text: "Frog result",
      structured_content: { results: [ { title: "Frog papers", url: "http://example.test/catalog/frogs" } ] }
    )
    allow(tool_runner).to receive(:call).with(name: "catalog_search_tool", arguments: { "query" => "toads" }).and_return(
      text: "Toad result",
      structured_content: { results: [ { title: "Toad papers", url: "http://example.test/catalog/toads" } ] }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "Compare frogs and toads" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(tool_runner).to have_received(:call).twice
    expect(client.requests.length).to eq(2)
    expect(client.requests.first.dig(:messages, 0, "content")).to include(
      "Prefer vector search for most discovery and research questions",
      "copy the user's current question verbatim into the query argument",
      "Use the supplied page value exactly",
      "Every citation must be a Markdown link"
    )
    expect(stream).to include("event: delta", "The corpus ", "event: sources")
    expect(stream).to include("Frog papers", "http://example.test/catalog/frogs")
    expect(stream).to include("Toad papers", "http://example.test/catalog/toads")
    expect(stream).to end_with("event: done\ndata: {}\n\n")
  end

  it "allows a refusal without making up a source" do
    client.enqueue(content: "I can only answer questions about the corpus.", deltas: [ "I can only answer questions about the corpus." ])
    allow(tool_runner).to receive(:call)

    stream = described_class.new(
      messages: [ { role: "user", content: "Write application code" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(tool_runner).not_to have_received(:call)
    expect(stream).not_to include("event: sources")
    expect(stream).to include("event: done")
  end

  it "reports a length-limited response as incomplete" do
    client.enqueue(content: "An unfinished answer", deltas: [ "An unfinished answer" ], finish_reason: "length")

    stream = described_class.new(
      messages: [ { role: "user", content: "Give me a long answer" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include("event: delta", "An unfinished answer", "event: error", "length limit")
    expect(stream).not_to include("event: done")
  end

  it "includes available page numbers with verified sources" do
    client.enqueue(tool_calls: [ tool_call("call-1", "Professor X") ])
    client.enqueue(content: "Professor X discussed a milestone.", deltas: [ "Professor X discussed a milestone." ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Passage results",
      structured_content: {
        passages: [
          {
            document_title: "Oral history with Professor X",
            url: "http://example.test/catalog/abc123",
            page: "28"
          },
          {
            document_title: "Oral history with Professor X",
            url: "http://example.test/catalog/abc123",
            page: "31"
          }
        ]
      }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "What milestone did Professor X discuss?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include(
      '"title":"Oral history with Professor X"',
      '"url":"http://example.test/catalog/abc123"',
      '"pages":["28","31"]'
    )
  end

  it "answers every requested tool call when the execution limit is reached" do
    allow(Rails.configuration.x.chat).to receive(:max_tool_calls).and_return(1)
    client.enqueue(tool_calls: [ tool_call("call-1", "frogs"), tool_call("call-2", "toads") ])
    client.enqueue(content: "The first search was sufficient.", deltas: [ "The first search was sufficient." ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Frog result",
      structured_content: { results: [ { title: "Frog papers", url: "http://example.test/catalog/frogs" } ] }
    )

    described_class.new(
      messages: [ { role: "user", content: "Compare frogs and toads" } ],
      client:,
      tool_runner:
    ).each_event.to_a

    expect(tool_runner).to have_received(:call).once
    final_request_messages = client.requests.last.fetch(:messages)
    expect(final_request_messages).to include(
      "role" => "tool",
      "tool_call_id" => "call-2",
      "content" => "The tool-call limit has been reached. Use the evidence already returned."
    )
  end

  it "rejects a transcript whose last message is not from the user" do
    expect do
      described_class.normalize_messages([ { role: "assistant", content: "Hello" } ])
    end.to raise_error(described_class::InvalidMessages, "The last message must be from the user.")
  end
end
