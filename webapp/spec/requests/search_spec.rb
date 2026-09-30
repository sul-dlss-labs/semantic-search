require 'rails_helper'

RSpec.describe "Searches", type: :request do
  def page_ids_are_unique?(body)
    ids = Nokogiri::HTML(body).css("[id]").map { |node| node["id"] }
    ids.tally.values.max == 1
  end

  describe "GET /" do
    it "performs a keyword search" do
      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "frogs" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("frogs")
      expect(response.body).to include('<option selected="selected" value="keyword">Keyword</option>')
    end

    it "shows the text that matched alongside the rest of each result's metadata" do
      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "education" }

      page = Nokogiri::HTML(response.body)
      metadata = page.at_css("article .document-metadata, article dl")
      expect(metadata.css("dt").map { |dt| dt.text.strip }).to include("Matching text:")
      expect(page.css(".matching-excerpt")).to be_present
      expect(page.css(".matching-excerpt mark")).to be_present
      expect(page.css(".matching-excerpt script")).to be_empty
    end

    it "still renders results when the excerpt query fails" do
      allow(MatchingExcerpts).to receive(:new).and_raise(Blacklight::Exceptions::InvalidRequest)

      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "education" }

      expect(response).to have_http_status(:success)
      expect(page_ids_are_unique?(response.body)).to be(true)
      expect(response.body).not_to include("matching-excerpt")
    end

    it "keeps excerpt element ids unique across the whole results page" do
      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "education" }

      expect(page_ids_are_unique?(response.body)).to be(true)
    end

    it "renders Search and Ask AI forms with Search selected by default" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#search-mode-search")["checked"]).to be_present
      expect(page.at_css("#search-mode-ai")["checked"]).to be_nil

      search_form = page.at_css('[data-search-mode-panel="search"] form')
      expect(search_form.at_css('select[name="search_type"]')).to be_present
      expect(search_form.at_css('button[type="submit"]').text.strip).to eq("Search")

      ai_form = page.at_css(".ai-search-query-form")
      expect(ai_form["action"]).to eq("/chat")
      expect(ai_form["method"]).to eq("get")
      expect(ai_form.at_css('input[name="q"]')["placeholder"]).to eq(AiSearchBarComponent::PLACEHOLDER)
      expect(ai_form.at_css('input[name="q"]')["maxlength"]).to eq(AiSearchBarComponent::MAX_CHARACTERS.to_s)
      expect(ai_form.at_css('button[type="submit"]').text.strip).to eq("Send")
      expect(ai_form.at_css("select")).to be_nil
      expect(ai_form.at_css('input[name="authenticity_token"]')).to be_nil
      expect(ai_form.css("svg.ai-prompt-icon, svg.ai-submit-icon").map { |icon| [ icon["width"], icon["height"] ] }).to eq([ [ "24", "24" ], [ "24", "24" ] ])
    end

    it "keeps the skip link visible in either mode and avoids duplicate element ids" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css('a[href="#search-bar"]')).to be_present
      expect(page.at_css("#search-bar")["tabindex"]).to eq("-1")
      ids = page.css("[id]").map { |node| node["id"] }
      expect(ids.tally.values.max).to eq(1)
    end
  end
end
