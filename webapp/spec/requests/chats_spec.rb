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
      expect(response.body).to include("Ask AI")
    end

    it "starts with Ask AI selected and prepares a submitted question for autostart" do
      get "/chat", params: { q: "frogs in ponds" }

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#search-mode-ai")["checked"]).to be_present
      expect(page.at_css(".chat-page")["data-chat-autostart-value"]).to eq("true")
      expect(page.at_css("#message").text.strip).to eq("frogs in ponds")
    end

    it "does not autostart an empty question and limits oversized URL input" do
      get "/chat", params: { q: "  " }
      expect(Nokogiri::HTML(response.body).at_css(".chat-page")["data-chat-autostart-value"]).to eq("false")

      limit = Rails.configuration.x.chat.max_message_characters
      get "/chat", params: { q: "a" * (limit + 100) }
      expect(Nokogiri::HTML(response.body).at_css("#message").text.strip.length).to eq(limit)
    end
  end

  describe "GET /chat with a search context" do
    let(:cocina_json) do
      { externalIdentifier: "druid:bb112zx3193", description: { title: [ { value: "Frogs" } ], note: [] } }.to_json
    end

    before do
      solr_response = Blacklight::Solr::Response.new(
        { "response" => { "numFound" => 417, "start" => 0,
                          "docs" => [ { id: "bb112zx3193", title_display_tesi: "Frog interview",
                                        collection_title_ss: "Frog Oral Histories", cocina_ss: cocina_json } ] } },
        { rows: 20 }, blacklight_config: CatalogController.blacklight_config
      )
      allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_return(solr_response)
    end

    it "shows what was carried over and prefills a question without sending it" do
      get "/chat", params: { search: { q: "frogs", page: "1" } }

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.at_css(".chat-context")).to be_present
      expect(page.at_css(".chat-context-summary").text.squish).to include("frogs", "417 matches", "showing 1–1")
      expect(page.at_css(".chat-context-list a").text).to eq("Frog interview")
      expect(page.at_css("#message").text.strip).to eq('What do these results tell me about "frogs"?')
      expect(page.at_css(".chat-page")["data-chat-autostart-value"]).to eq("false")
    end

    it "signs the carried context into the form so every turn replays it" do
      get "/chat", params: { search: { q: "frogs" } }

      field = Nokogiri::HTML(response.body).at_css('input[name="context_token"]')
      expect(field["data-chat-target"]).to eq("contextToken")
      expect(Chat::SearchContext.from_token(field["value"]).query).to eq("frogs")
    end

    it "keeps the active filters visible and available to remove" do
      get "/chat", params: { search: { q: "frogs", f: { "collection_title_ss" => [ "Frog Oral Histories" ] } } }

      page = Nokogiri::HTML(response.body)
      expect(page.at_css(".chat-context-filter").text.squish).to include("Collection:", "Frog Oral Histories")
      expect(page.at_css(".chat-context-remove")["data-action"]).to eq("chat#removeContext")
    end

    it "stays usable and says so when the carried search cannot be rebuilt" do
      allow(Chat::SearchContext).to receive(:from_search_params).and_return(nil)

      get "/chat", params: { search: { q: "frogs" } }

      page = Nokogiri::HTML(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.at_css(".alert-warning").text).to include("no longer available")
      expect(page.at_css(".chat-context")).to be_nil
      expect(page.at_css('input[name="context_token"]')).to be_nil
    end

    it "does not render a context card when no search was carried" do
      get "/chat"

      expect(Nokogiri::HTML(response.body).at_css(".chat-context, .alert-warning")).to be_nil
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
        controller: an_instance_of(ChatsController),
        search_context: nil
      )
    end

    it "scopes the conversation to a validly signed search context" do
      conversation = instance_double(Chat::Conversation, each_event: [ "event: done\ndata: {}\n\n" ].each)
      allow(Chat::Conversation).to receive(:new).and_return(conversation)
      token = Chat::SearchContext.verifier.generate({ version: 1, query: "frogs", documents: [] })

      post "/chat", params: { messages: [ { role: "user", content: "frogs" } ], context_token: token }, as: :json

      expect(Chat::Conversation).to have_received(:new).with(
        hash_including(search_context: an_instance_of(Chat::SearchContext))
      )
    end

    it "answers without the context rather than failing the turn on a bad token" do
      conversation = instance_double(Chat::Conversation, each_event: [ "event: done\ndata: {}\n\n" ].each)
      allow(Chat::Conversation).to receive(:new).and_return(conversation)

      post "/chat", params: { messages: [ { role: "user", content: "frogs" } ], context_token: "tampered" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Chat::Conversation).to have_received(:new).with(hash_including(search_context: nil))
    end

    it "rejects an invalid transcript" do
      post "/chat", params: { messages: [] }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.fetch("error")).to include("messages")
    end
  end
end
