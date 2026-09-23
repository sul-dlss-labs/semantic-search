# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat", type: :request do
  describe "GET /chat" do
    it "renders the public chat interface" do
      get "/chat"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ask AI about the collections", "data-controller=\"chat\"")
      expect(response.body).to match(%r{/assets/chat-[^\"]+\.css})
      expect(response.body).to include('data-turbo-track="dynamic"')
      expect(response.body).to include("Ask AI")
    end

    it "preselects Ask AI in the navbar toggle" do
      get "/chat"

      toggle = Nokogiri::HTML(response.body).at_css("#search-mode-ai")
      expect(toggle["checked"]).to be_present
      expect(Nokogiri::HTML(response.body).at_css("#search-mode-search")["checked"]).to be_nil
    end

    it "prefills the question from the navbar and asks it without a second click" do
      get "/chat", params: { q: "frogs in ponds" }

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".chat-page")["data-chat-autostart-value"]).to eq("true")
      expect(page.at_css("#message").text.strip).to eq("frogs in ponds")
    end

    it "does not autostart without a question" do
      get "/chat"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".chat-page")["data-chat-autostart-value"]).to eq("false")
      expect(page.at_css("#message").text.strip).to be_empty
    end

    it "clamps an oversized question rather than trusting the textarea maxlength" do
      limit = Rails.configuration.x.chat.max_message_characters
      get "/chat", params: { q: "a" * (limit + 100) }

      expect(Nokogiri::HTML(response.body).at_css("#message").text.strip.length).to eq(limit)
    end
  end

  describe "POST /chat" do
    it "returns the conversation as a server-sent event stream" do
      conversation = instance_double(Chat::Conversation, each_event: [ "event: done\ndata: {}\n\n" ].each)
      allow(Chat::Conversation).to receive(:new).and_return(conversation)

      post "/chat", params: { messages: [ { role: "user", content: "frogs" } ] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/event-stream")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Last-Modified"]).to be_present
      expect(response.body).to eq("event: done\ndata: {}\n\n")
      expect(Chat::Conversation).to have_received(:new).with(
        messages: [ { "role" => "user", "content" => "frogs" } ],
        controller: an_instance_of(ChatsController)
      )
    end

    it "rejects an invalid transcript" do
      post "/chat", params: { messages: [] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("error")).to include("messages")
    end
  end
end
