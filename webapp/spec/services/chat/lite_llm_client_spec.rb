# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::LiteLlmClient do
  subject(:client) { described_class.new }

  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }
  let(:messages) do
    [
      { "role" => "system", "content" => "Use the corpus." },
      { "role" => "user", "content" => "Tell me about frogs." }
    ]
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LITELLM_API_BASE").and_return("https://litellm.example/v1/")
    allow(ENV).to receive(:[]).with("LITELLM_API_KEY").and_return("proxy-key")
    allow(ENV).to receive(:[]).with("LITELLM_CHAT_MODEL").and_return("chat-alias")
    allow(Net::HTTP).to receive(:new).with("litellm.example", 443).and_return(http)
    allow(http).to receive(:use_ssl=).with(true)
    allow(http).to receive(:open_timeout=).with(10)
    allow(http).to receive(:read_timeout=).with(120)
  end

  it "streams content from the LiteLLM chat completions endpoint" do
    chunks = [
      %(data: {"id":"chat-123","choices":[{"delta":{"content":"Frogs "}}]}\n\n),
      %(data: {"choices":[{"delta":{"content":"appear."}}]}\n\n),
      %(data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n),
      %(data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":3,"total_tokens":13}}\n\n),
      "data: [DONE]\n\n"
    ]
    allow(response).to receive(:read_body) { |&block| chunks.each(&block) }
    allow(http).to receive(:request) do |request, &block|
      expect(request.uri.to_s).to eq("https://litellm.example/v1/chat/completions")
      expect(request["Authorization"]).to eq("Bearer proxy-key")
      expect(JSON.parse(request.body)).to include(
        "model" => "chat-alias",
        "messages" => messages,
        "max_tokens" => 4_000,
        "stream" => true,
        "stream_options" => { "include_usage" => true }
      )
      block.call(response)
    end

    deltas = []
    completion = client.stream_completion(messages:) { |delta| deltas << delta }

    expect(deltas).to eq([ "Frogs ", "appear." ])
    expect(completion.message).to eq("role" => "assistant", "content" => "Frogs appear.")
    expect(completion.tool_calls).to be_empty
    expect(completion.finish_reason).to eq("stop")
  end

  it "assembles streamed tool-call fragments" do
    chunks = [
      %(data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"catalog_","arguments":"{\\"query\\":"}}]}}]}\n\n),
      %(data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"search_tool","arguments":"\\"frogs\\"}"}}]}}]}\n\n),
      %(data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n),
      "data: [DONE]\n\n"
    ]
    allow(response).to receive(:read_body) { |&block| chunks.each(&block) }
    allow(http).to receive(:request) { |_request, &block| block.call(response) }

    completion = client.stream_completion(messages:, tools: [ { type: "function" } ])

    expect(completion.tool_calls).to eq(
      [
        {
          "id" => "call-1",
          "type" => "function",
          "function" => { "name" => "catalog_search_tool", "arguments" => '{"query":"frogs"}' }
        }
      ]
    )
    expect(completion).to be_complete
  end

  it "can explicitly disable tool calls for a forced final response" do
    chunks = [
      %(data: {"choices":[{"delta":{"content":"Final answer."},"finish_reason":"stop"}]}\n\n),
      "data: [DONE]\n\n"
    ]
    allow(response).to receive(:read_body) { |&block| chunks.each(&block) }
    allow(http).to receive(:request) do |request, &block|
      expect(JSON.parse(request.body)).to include(
        "tools" => [ { "type" => "function" } ],
        "tool_choice" => "none"
      )
      block.call(response)
    end

    completion = client.stream_completion(
      messages:,
      tools: [ { type: "function" } ],
      tool_choice: "none"
    )

    expect(completion.message["content"]).to eq("Final answer.")
  end

  it "rejects a stream that ends without its done event" do
    chunks = [ %(data: {"choices":[{"delta":{"content":"An incomplete answer"}}]}\n\n) ]
    allow(response).to receive(:read_body) { |&block| chunks.each(&block) }
    allow(http).to receive(:request) { |_request, &block| block.call(response) }

    expect { client.stream_completion(messages:) }
      .to raise_error(described_class::RequestError, "LiteLLM stream ended before its done event")
  end

  it "requires a configured chat model" do
    allow(ENV).to receive(:[]).with("LITELLM_CHAT_MODEL").and_return(nil)

    expect { client.stream_completion(messages:) }
      .to raise_error(RuntimeError, "LITELLM_CHAT_MODEL environment variable is not set")
  end

  it "includes bounded LiteLLM error details in server-side exceptions" do
    error_response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    allow(error_response).to receive(:body).and_return(
      { error: { message: 'Unknown name "additionalProperties" in tool parameters' } }.to_json
    )
    allow(http).to receive(:request) { |_request, &block| block.call(error_response) }

    expect { client.stream_completion(messages:) }
      .to raise_error(
        described_class::RequestError,
        'LiteLLM chat request failed (400): Unknown name "additionalProperties" in tool parameters'
      )
  end
end
