require 'rails_helper'

RSpec.describe "Searches", type: :request do
  def page_ids_are_unique?(body)
    ids = Nokogiri::HTML(body).css("[id]").map { |node| node["id"] }
    ids.tally.values.max == 1
  end

  describe "GET /" do
    it "classifies a catalog search and keeps the strategy out of the search form" do
      get "/", params: { search_field: "all_fields", q: "Interview with John Lynch", search_type: "vector" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Interview with John Lynch")
      expect(Search.last.query_params["search_type"]).to eq("keyword")
      expect(Nokogiri::HTML(response.body).at_css('form.search-query-form [name="search_type"]')).to be_nil
    end

    context "with matching excerpts" do
      # CI's Solr core is empty, so supply the result page directly. Title-like queries classify
      # as keyword searches, which keeps LiteLLM out of the request.
      let(:query) { "Water Rights" }
      let(:results) do
        docs = { "bb191qg8085" => "Water Rights", "bb205zt9580" => "Riparian Law" }.map do |id, title|
          cocina = { externalIdentifier: "druid:#{id}", description: { title: [ { value: title } ], note: [] } }
          { "id" => id, "doc_type_ssi" => "parent", "title_tsim" => [ title ], "cocina_ss" => cocina.to_json }
        end
        Blacklight::Solr::Response.new(
          { "response" => { "numFound" => docs.length, "start" => 0, "docs" => docs } },
          {}, blacklight_config: CatalogController.blacklight_config, document_model: SolrDocument
        )
      end

      before do
        allow_any_instance_of(Blacklight::SearchService).to receive(:search_results).and_return(results)
        allow(MatchingExcerpts).to receive(:new)
      end

      it "leaves the excerpts out of the page render and loads them afterwards" do
        get "/", params: { search_field: "all_fields", q: query }

        page = Nokogiri::HTML(response.body)
        expect(MatchingExcerpts).not_to have_received(:new)
        expect(page.css("article dd[aria-busy]").pluck("id"))
          .to eq(%w[matching-excerpts-slot-bb191qg8085 matching-excerpts-slot-bb205zt9580])
        expect(page.css("article dt.matching-excerpts-pending").map { |dt| dt.text.strip })
          .to eq([ "Matching text:", "Matching text:" ])
        expect(page.css(".matching-excerpt")).to be_empty

        expect(page.at_css("turbo-frame#matching-excerpts")["src"])
          .to eq(matching_excerpts_path(q: query, ids: %w[bb191qg8085 bb205zt9580]))
      end

      it "keeps excerpt element ids unique across the whole results page" do
        get "/", params: { search_field: "all_fields", q: query }

        expect(page_ids_are_unique?(response.body)).to be(true)
      end

      it "leaves out the placeholders and loader when there is no query" do
        get "/", params: { search_field: "all_fields", f: { format_hsim: [ "Text" ] } }

        expect(response.body).not_to include("matching-excerpts")
      end
    end

    it "renders Search and Ask AI forms with Search selected by default" do
      get "/"

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("#search-mode-search")["checked"]).to be_present
      expect(page.at_css("#search-mode-ai")["checked"]).to be_nil

      search_form = page.at_css('[data-search-mode-panel="search"] form')
      expect(search_form.at_css('[name="search_type"]')).to be_nil
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
