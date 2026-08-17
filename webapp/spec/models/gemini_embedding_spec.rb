# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeminiEmbedding do
  subject(:client) { described_class.new }

  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LITELLM_API_BASE").and_return("https://litellm.example/v1/")
    allow(ENV).to receive(:[]).with("LITELLM_API_KEY").and_return("proxy-key")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("LITELLM_EMBEDDING_MODEL", described_class::MODEL)
      .and_return(described_class::MODEL)
    allow(Net::HTTP).to receive(:new).with("litellm.example", 443).and_return(http)
    allow(http).to receive(:use_ssl=).with(true)
    allow(response).to receive(:body).and_return(
      {
        id: "embedding-request-123",
        data: [
          { index: 1, embedding: [ 0.3, 0.4 ] },
          { index: 0, embedding: [ 0.1, 0.2 ] }
        ],
        usage: { prompt_tokens: 7, total_tokens: 7 }
      }.to_json
    )
  end

  it "sends a batched, authenticated request to the LiteLLM embeddings endpoint" do
    allow(http).to receive(:request) do |request|
      expect(request).to be_a(Net::HTTP::Post)
      expect(request.uri.to_s).to eq("https://litellm.example/v1/embeddings")
      expect(request["Authorization"]).to eq("Bearer proxy-key")
      expect(JSON.parse(request.body)).to eq(
        "model" => "gemini-embedding-2",
        "input" => [ "first", "second" ],
        "dimensions" => 768
      )
      response
    end

    expect(client.embedding(input: [ "first", "second" ])).to eq([ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ])
  end

  it "instruments the request without including input text or credentials" do
    allow(http).to receive(:request).and_return(response)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(described_class::INSTRUMENTATION_EVENT) do |event|
      events << event
    end

    client.embedding(input: [ "sensitive first", "sensitive second" ], instruction: "search result")

    expect(events.length).to eq(1)
    expect(events.first.payload).to include(
      model: "gemini-embedding-2",
      operation: "embeddings",
      input_count: 2,
      input_characters: 89,
      instruction_present: true,
      dimensions: 768,
      http_status: 200,
      response_id: "embedding-request-123",
      prompt_tokens: 7,
      total_tokens: 7
    )
    expect(events.first.payload.to_json).not_to include("sensitive", "proxy-key")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  it "preserves the query instruction formatting" do
    allow(http).to receive(:request) do |request|
      expect(JSON.parse(request.body).fetch("input")).to eq([ "task: search result | query: frogs" ])
      allow(response).to receive(:body).and_return({ data: [ { index: 0, embedding: [ 0.1 ] } ] }.to_json)
      response
    end

    client.embedding(input: [ "frogs" ], instruction: described_class::DEFAULT_QUERY_INSTRUCTION)
  end

  it "requires the LiteLLM proxy configuration" do
    allow(ENV).to receive(:[]).with("LITELLM_API_BASE").and_return(nil)

    expect { client.embedding(input: [ "text" ]) }
      .to raise_error(RuntimeError, "LITELLM_API_BASE environment variable is not set")
  end

  it "includes LiteLLM error details when a request fails" do
    error_response = Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized")
    allow(error_response).to receive(:body).and_return('{"error":"invalid key"}')
    allow(http).to receive(:request).and_return(error_response)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(described_class::INSTRUMENTATION_EVENT) do |event|
      events << event
    end

    expect { client.embedding(input: [ "text" ]) }
      .to raise_error(RuntimeError, 'LiteLLM embedding request failed (401): {"error":"invalid key"}')
    expect(events.length).to eq(1)
    expect(events.first.payload).to include(http_status: 401)
    expect(events.first.payload.fetch(:exception).first).to eq("RuntimeError")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
