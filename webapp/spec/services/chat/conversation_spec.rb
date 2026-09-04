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

    def stream_completion(messages:, tools:, tool_choice: nil)
      @requests << { messages:, tools:, tool_choice: }
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
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => "Compare frogs and toads" }
    ).and_return(text: "No passages", structured_content: { passages: [] })
    allow(tool_runner).to receive(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "Compare frogs and toads", "search_type" => "vector", "rows" => 10 }
    ).and_return(text: "No catalog results", structured_content: { results: [] })

    stream = described_class.new(
      messages: [ { role: "user", content: "Compare frogs and toads" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(tool_runner).to have_received(:call).exactly(4).times
    expect(client.requests.length).to eq(2)
    expect(client.requests.first.dig(:messages, 0, "content")).to include(
      "Prefer vector search for most discovery and research questions",
      "copy the user's current question verbatim into the query argument",
      "automatically pairs the first discovery call",
      "Use the supplied page value exactly",
      "Every citation must be a Markdown link"
    )
    expect(stream).to include("event: delta", "The corpus ", "event: sources")
    expect(stream).to include("Frog papers", "http://example.test/catalog/frogs")
    expect(stream).to include("Toad papers", "http://example.test/catalog/toads")
    expect(stream).to end_with("event: done\ndata: {}\n\n")
  end

  it "pairs the first discovery call with verbatim global, catalog, and document-constrained searches" do
    question = "Who died after a fall while descending a mountain in Iran?"
    client.enqueue(tool_calls: [ tool_call("call-1", "mountain death") ])
    client.enqueue(content: "Kathleen Namphy died after the fall.", deltas: [ "Kathleen Namphy died after the fall." ])
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => question }
    ).and_return(
      text: "Found an unrelated death",
      structured_content: {
        passages: [
          {
            rank: 1,
            text: "An unrelated person died elsewhere.",
            document_id: "unrelated",
            document_title: "Unrelated source",
            url: "/catalog/unrelated"
          }
        ]
      }
    )
    allow(tool_runner).to receive(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => question, "search_type" => "vector", "rows" => 10 }
    ).and_return(
      text: "Found the volume",
      structured_content: {
        results: [ { id: "vm857hw3603", title: "Stanford report", url: "/catalog/vm857hw3603" } ]
      }
    )
    allow(tool_runner).to receive(:call).with(
      name: "search_passages",
      arguments: { "query" => question, "document_ids" => [ "vm857hw3603" ] }
    ).and_return(
      text: "Found Kathleen Namphy",
      structured_content: {
        passages: [
          {
            rank: 1,
            text: "Kathleen Namphy was injured while descending Mount Damavand.",
            document_id: "vm857hw3603",
            document_title: "Stanford report",
            url: "/catalog/vm857hw3603"
          }
        ]
      }
    )
    allow(tool_runner).to receive(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "mountain death" }
    ).and_return(
      text: "No fallback results",
      structured_content: { results: [] }
    )

    described_class.new(
      messages: [ { role: "user", content: question } ],
      client:,
      tool_runner:
    ).each_event.to_a

    expect(tool_runner).to have_received(:call).with(
      name: "search_passages",
      arguments: { "query" => question }
    ).ordered
    expect(tool_runner).to have_received(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => question, "search_type" => "vector", "rows" => 10 }
    ).ordered
    expect(tool_runner).to have_received(:call).with(
      name: "search_passages",
      arguments: { "query" => question, "document_ids" => [ "vm857hw3603" ] }
    ).ordered
    expect(tool_runner).to have_received(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "mountain death" }
    ).ordered
    tool_message = client.requests.last.fetch(:messages).find { |message| message["role"] == "tool" }
    expect(tool_message.fetch("content")).to match(
      /Kathleen Namphy.*An unrelated person/m
    )
  end

  it "skips document-constrained discovery when catalog search has no usable document ids" do
    question = "Which frog?"
    client.enqueue(tool_calls: [ tool_call("call-1", question) ])
    client.enqueue(content: "No frog was identified.", deltas: [ "No frog was identified." ])
    allow(tool_runner).to receive(:call).and_return(text: "No results", structured_content: { results: [], passages: [] })

    described_class.new(
      messages: [ { role: "user", content: question } ],
      client:,
      tool_runner:
    ).each_event.to_a

    expect(tool_runner).to have_received(:call).exactly(3).times
    expect(tool_runner).not_to have_received(:call).with(
      name: "search_passages",
      arguments: hash_including("document_ids")
    )
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

  it "notifies the user when the source event is capped" do
    allow(Rails.configuration.x.chat).to receive(:max_sources).and_return(1)
    allow(Rails.configuration.x.chat).to receive(:max_source_event_characters).and_return(64_000)
    client.enqueue(tool_calls: [ tool_call("call-1", "frogs") ])
    client.enqueue(content: "The evidence supports the answer.", deltas: [ "The evidence supports the answer." ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Results",
      structured_content: {
        results: [
          { title: "Frog papers", url: "http://example.test/catalog/frogs" },
          { title: "Frog history", url: "http://example.test/catalog/history" }
        ]
      }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "Which frog?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include("event: notice", "Your query returned more research than can be displayed")
    expect(stream.scan('"url":"http://example.test/catalog/').length).to eq(1)
  end

  it "replaces a verified bare citation with a Markdown link" do
    title = "Stanford report. Volume 36, 2003-2004"
    url = "http://example.test/catalog/vm857hw3603"
    bare_answer = "Kathleen Namphy died after the fall #{title}, p. 571."
    client.enqueue(tool_calls: [ tool_call("call-1", "mountain fall") ])
    client.enqueue(content: bare_answer, deltas: [ bare_answer ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Kathleen Namphy result",
      structured_content: {
        passages: [ { document_title: title, url:, page: "571" } ]
      }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "Who fell while descending Mount Damavand?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include("event: reset")
    expect(stream).to include(
      JSON.generate(content: "Kathleen Namphy died after the fall [#{title}, p. 571](<#{url}>).")
    )
    expect(stream.index("event: sources")).to be < stream.index("event: delta", stream.index("event: reset"))
    expect(stream).to end_with("event: done\ndata: {}\n\n")
  end

  it "links a cited source collected after the first ten sources" do
    sources = 11.times.map do |index|
      {
        title: "Source #{index + 1}",
        url: "http://example.test/catalog/source-#{index + 1}"
      }
    end
    cited_source = sources.last
    bare_answer = "The decisive evidence appears in #{cited_source[:title]}, p. 29."
    client.enqueue(tool_calls: [ tool_call("call-1", "decisive evidence") ])
    client.enqueue(content: bare_answer, deltas: [ bare_answer ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Search results",
      structured_content: { results: sources }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "Where does the decisive evidence appear?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include(
      JSON.generate(content: "The decisive evidence appears in " \
                             "[#{cited_source[:title]}, p. 29](<#{cited_source[:url]}>).")
    )
    expect(stream).to include(JSON.generate(cited_source))
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

    expect(tool_runner).to have_received(:call).exactly(3).times
    expect(tool_runner).not_to have_received(:call).with(
      name: "catalog_search_tool",
      arguments: { "query" => "toads" }
    )
    final_request_messages = client.requests.last.fetch(:messages)
    expect(final_request_messages).to include(
      "role" => "tool",
      "tool_call_id" => "call-2",
      "content" => "The tool-call limit has been reached. Use the evidence already returned."
    )
  end

  it "forces a text response and retries a tool-only final completion" do
    allow(Rails.configuration.x.chat).to receive(:max_tool_rounds).and_return(1)
    client.enqueue(tool_calls: [ tool_call("call-1", "frogs") ])
    client.enqueue(tool_calls: [ tool_call("call-2", "more frogs") ], finish_reason: "tool_calls")
    client.enqueue(content: "The evidence identifies a frog.", deltas: [ "The evidence identifies a frog." ])
    allow(tool_runner).to receive(:call).and_return(
      text: "Frog result",
      structured_content: { results: [ { title: "Frog papers", url: "http://example.test/catalog/frogs" } ] }
    )

    stream = described_class.new(
      messages: [ { role: "user", content: "Which frog?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(client.requests.last(2)).to all(include(tools: tool_runner.definitions, tool_choice: "none"))
    expect(stream).to include("The evidence identifies a frog.", "event: done")
  end

  it "reports an error when both forced final completions contain no text" do
    allow(Rails.configuration.x.chat).to receive(:max_tool_rounds).and_return(1)
    client.enqueue(tool_calls: [ tool_call("call-1", "frogs") ])
    client.enqueue(tool_calls: [ tool_call("call-2", "more frogs") ], finish_reason: "tool_calls")
    client.enqueue(finish_reason: "stop")
    allow(tool_runner).to receive(:call).and_return(text: "No result", structured_content: { results: [] })

    stream = described_class.new(
      messages: [ { role: "user", content: "Which frog?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to include("event: error", "could not produce an answer")
    expect(stream).not_to include("event: done")
  end

  it "stops quietly when the browser hangs up mid-stream" do
    allow(Rails.logger).to receive(:info)
    allow(client).to receive(:stream_completion).and_raise(Errno::EPIPE)

    stream = described_class.new(
      messages: [ { role: "user", content: "Which frog?" } ],
      client:,
      tool_runner:
    ).each_event.to_a.join

    expect(stream).to be_empty
    expect(Rails.logger).to have_received(:info).with(/Chat client disconnected mid-stream: Errno::EPIPE/)
  end

  it "does not raise when the browser hangs up while the error event is being sent" do
    allow(Rails.logger).to receive(:info)
    allow(client).to receive(:stream_completion).and_raise(StandardError, "LiteLLM is down")
    events = described_class.new(
      messages: [ { role: "user", content: "Which frog?" } ],
      client:,
      tool_runner:
    ).each_event

    expect { events.each { raise Errno::ECONNRESET } }.not_to raise_error
    expect(Rails.logger).to have_received(:info)
      .with(/Chat client disconnected before the error event was sent: Errno::ECONNRESET/)
  end

  it "rejects a transcript whose last message is not from the user" do
    expect do
      described_class.normalize_messages([ { role: "assistant", content: "Hello" } ])
    end.to raise_error(described_class::InvalidMessages, "The last message must be from the user.")
  end
end
