# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/chat_evaluation/remote_chat_client")

RSpec.describe Chat::Evaluation::RemoteChatClient do
  describe "#ask" do
    let(:get_http) { instance_double(Net::HTTP) }
    let(:post_http) { instance_double(Net::HTTP) }
    let(:get_response) { Net::HTTPOK.new("1.1", "200", "OK") }
    let(:post_response) { Net::HTTPOK.new("1.1", "200", "OK") }

    before do
      allow(Net::HTTP).to receive(:new).with("chat.example", 443).and_return(get_http, post_http)
      [ get_http, post_http ].each do |http|
        allow(http).to receive(:use_ssl=).with(true)
        allow(http).to receive(:open_timeout=).with(10)
      end
      allow(get_http).to receive(:read_timeout=).with(180)
      allow(post_http).to receive(:read_timeout=).with(180)
      allow(get_response).to receive(:body).and_return(
        '<html><head><meta name="csrf-token" content="token&amp;value"></head></html>'
      )
      allow(get_response).to receive(:get_fields).with("set-cookie").and_return(
        [ "session=abc123; path=/; secure", "preference=compact; path=/" ]
      )
      allow(get_http).to receive(:request).and_return(get_response)
    end

    it "submits the question and assembles the streamed answer and sources" do
      chunks = [
        "event: delta\ndata: {\"content\":\"Searching...\"}\n\n",
        "event: reset\ndata: {}\n\n",
        "event: delta\ndata: {\"content\":\"John Lynch threw \"}\n\n",
        "event: delta\ndata: {\"content\":\"the first pitch.\"}\n\n",
        "event: sources\ndata: {\"sources\":[{\"title\":\"Baseball history\",\"url\":\"https://example.test/baseball\"}]}\n\n",
        "event: done\ndata: {}\n\n"
      ]
      allow(post_response).to receive(:read_body) { |&block| chunks.each(&block) }
      allow(post_http).to receive(:request) do |request, &block|
        expect(request.uri.to_s).to eq("https://chat.example/chat")
        expect(request["Accept"]).to eq("text/event-stream")
        expect(request["X-CSRF-Token"]).to eq("token&value")
        expect(request["Cookie"]).to eq("session=abc123; preference=compact")
        expect(JSON.parse(request.body)).to eq(
          "messages" => [
            { "role" => "user", "content" => "Who threw the first pitch?" },
            { "role" => "assistant", "content" => "I could not find it." },
            { "role" => "user", "content" => "Who threw it?" }
          ]
        )
        block.call(post_response)
      end

      result = described_class.new(base_url: "https://chat.example").ask(
        "Who threw it?",
        history: [
          { role: "user", content: "Who threw the first pitch?" },
          { role: "assistant", content: "I could not find it." }
        ]
      )

      expect(result.answer).to eq("John Lynch threw the first pitch.")
      expect(result.sources).to eq(
        [ { "title" => "Baseball history", "url" => "https://example.test/baseball" } ]
      )
    end
  end

  describe Chat::Evaluation::RemoteChatClient::StreamAccumulator do
    it "turns a server error event into an exception" do
      accumulator = described_class.new

      expect do
        accumulator.feed("event: error\ndata: {\"message\":\"Unavailable\"}\n\n")
      end.to raise_error(Chat::Evaluation::RemoteChatClient::RequestError, "Unavailable")
    end
  end
end
