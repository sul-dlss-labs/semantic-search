require 'rails_helper'

RSpec.describe "Searches", type: :request do
  describe "GET /" do
    it "performs a keyword search" do
      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "frogs" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("frogs")
      expect(response.body).to include('<option selected="selected" value="keyword">Keyword</option>')
    end

    it "offers both search modes in the navbar, defaulting to keyword search" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#search-mode-search")["checked"]).to be_present
      expect(page.at_css("#search-mode-ai")["checked"]).to be_nil

      ai_form = page.at_css(".ai-search-query-form")
      expect(ai_form["action"]).to eq("/chat")
      expect(ai_form["method"]).to eq("get")
      expect(ai_form.at_css("#ai-question")["placeholder"]).to eq("Ask a question about our collections")
      expect(ai_form.at_css("#ai-question-submit").text.strip).to eq("Send")
      expect(ai_form.at_css("select")).to be_nil

      # A GET carries the question in the request line, so it must not be unbounded.
      expect(ai_form.at_css("#ai-question")["maxlength"]).to eq(AiSearchBarComponent::MAX_CHARACTERS.to_s)

      # No authenticity token, _method, or utf8 param should end up in the URL.
      expect(ai_form.css("input[name='authenticity_token'], input[name='_method'], input[name='utf8']")).to be_empty
    end

    it "prompts differently in each mode" do
      get "/"

      page = Nokogiri::HTML(response.body)
      # Keyword search keeps Blacklight's own placeholder, so assert the two differ rather than
      # pinning the gem's wording.
      expect(page.at_css("#q")["placeholder"]).to be_present
      expect(page.at_css("#q")["placeholder"]).not_to eq(page.at_css("#ai-question")["placeholder"])
    end

    it "keeps the skip link pointed at something visible in both modes" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.css("a[href='#search-bar']")).not_to be_empty
      expect(page.css("a[href='#search_field'], a[href='#q']")).to be_empty

      target = page.at_css("#search-bar")
      expect(target).to be_present
      # Without tabindex the browser scrolls to the anchor but leaves focus on the skip link.
      expect(target["tabindex"]).to eq("-1")
      expect(target["aria-label"]).to be_present
    end

    it "keeps element ids unique now that two search forms share the navbar" do
      get "/"

      ids = Nokogiri::HTML(response.body).css("[id]").map { |node| node["id"] }
      expect(ids.tally.select { |_, count| count > 1 }).to be_empty
    end
  end
end
