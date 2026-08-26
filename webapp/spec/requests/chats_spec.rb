# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Chat", type: :request do
  describe "GET /chat" do
    it "renders the public chat interface" do
      get "/chat"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chat with the collections", "data-controller=\"chat\"")
      expect(response.body).to match(%r{/assets/chat-[^\"]+\.css})
      expect(response.body).to include('data-turbo-track="dynamic"')
      expect(response.body).to include("Chat with collections")
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
