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

    context "with a search context" do
      let(:search_context) { { q: "band auditions", f: { "collection_title_ss" => [ "Oral Histories" ] } } }

      it "loads the chat page with the search so the deployment mints the token, then replays it" do
        allow(get_response).to receive(:body).and_return(
          '<html><head><meta name="csrf-token" content="csrf"></head>' \
          '<body><input type="hidden" name="context_token" value="signed&amp;token"></body></html>'
        )
        allow(post_response).to receive(:read_body) { |&block| block.call("event: done\ndata: {}\n\n") }
        allow(get_http).to receive(:request) do |request|
          expect(request.uri.query).to eq(
            "search%5Bf%5D%5Bcollection_title_ss%5D%5B%5D=Oral+Histories&search%5Bq%5D=band+auditions"
          )
          get_response
        end
        allow(post_http).to receive(:request) do |request, &block|
          expect(JSON.parse(request.body)["context_token"]).to eq("signed&token")
          block.call(post_response)
        end

        described_class.new(base_url: "https://chat.example").ask("What is here?", search_context:)

        expect(post_http).to have_received(:request)
      end

      it "fails loudly when the page carries no context, rather than evaluating an unscoped answer" do
        allow(get_response).to receive(:body).and_return(
          '<html><head><meta name="csrf-token" content="csrf"></head></html>'
        )

        expect do
          described_class.new(base_url: "https://chat.example").ask("What is here?", search_context:)
        end.to raise_error(described_class::RequestError, /did not carry a search context/)
      end
    end
  end

  describe Chat::Evaluation::RemoteChatClient::StreamAccumulator do
    it "records notices and flags a length-limited answer as truncated" do
      accumulator = described_class.new
      accumulator.feed("event: delta\ndata: {\"content\":\"An unfinished\"}\n\n")
      accumulator.feed(
        "event: notice\ndata: {\"message\":\"This response reached its length limit and may be incomplete.\"}\n\n"
      )
      accumulator.feed("event: done\ndata: {}\n\n")

      result = accumulator.finish

      expect(result.answer).to eq("An unfinished")
      expect(result.notices).to eq([ "This response reached its length limit and may be incomplete." ])
      expect(result).to be_truncated
    end

    it "does not flag other notices as truncation" do
      accumulator = described_class.new
      accumulator.feed("event: notice\ndata: {\"message\":\"Your query returned more research than can be displayed.\"}\n\n")
      accumulator.feed("event: done\ndata: {}\n\n")

      expect(accumulator.finish).not_to be_truncated
    end

    it "turns a server error event into an exception" do
      accumulator = described_class.new

      expect do
        accumulator.feed("event: error\ndata: {\"message\":\"Unavailable\"}\n\n")
      end.to raise_error(Chat::Evaluation::RemoteChatClient::RequestError, "Unavailable")
    end
  end
end
