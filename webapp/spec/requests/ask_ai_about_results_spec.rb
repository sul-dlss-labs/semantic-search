# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ask AI about these results", type: :request do
  let(:cocina_json) do
    { externalIdentifier: "druid:bb112zx3193", description: { title: [ { value: "Frogs" } ], note: [] } }.to_json
  end

  def stub_solr(total: 417, docs: [ { id: "bb112zx3193", title_display_tesi: "Frog interview", cocina_ss: cocina_json } ])
    response = Blacklight::Solr::Response.new(
      { "response" => { "numFound" => total, "start" => 0, "docs" => docs } },
      { rows: 20 }, blacklight_config: CatalogController.blacklight_config
    )
    allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_return(response)
  end

  def button
    Nokogiri::HTML(response.body).at_css(".ask-ai-results-button")
  end

  it "links to the chat with the search the user is looking at" do
    stub_solr
    get "/", params: { q: "frogs", search_type: "keyword", page: "2",
                       f: { "collection_title_ss" => [ "Frog Oral Histories" ] } }

    expect(button.text.strip).to eq("Ask AI about these results")
    carried = Rack::Utils.parse_nested_query(URI.parse(button["href"]).query).fetch("search")
    expect(carried).to include("q" => "frogs", "page" => "2")
    expect(carried.dig("f", "collection_title_ss")).to eq([ "Frog Oral Histories" ])
  end

  it "explains what gets sent to the assistant before the user clicks" do
    stub_solr
    get "/", params: { q: "frogs", search_type: "keyword" }

    page = Nokogiri::HTML(response.body)
    hint = page.at_css("#ask-ai-results-hint")
    expect(button["aria-describedby"]).to eq("ask-ai-results-hint")
    expect(hint.text.squish).to eq("Opens the AI chat with your search query, your facet selections, and this page of results.")
  end

  it "offers the assistant on a facet-only browse, which has no query to summarize" do
    stub_solr
    get "/", params: { f: { "collection_title_ss" => [ "Frog Oral Histories" ] } }

    expect(button).to be_present
    expect(Nokogiri::HTML(response.body).at_css("[data-controller='ai-summary']")).to be_nil
  end

  it "offers the assistant on a zero-result search, where it is most useful" do
    stub_solr(total: 0, docs: [])
    get "/", params: { q: "nothing here", search_type: "keyword" }

    expect(button.text.strip).to eq("Ask AI about this search")
    expect(Nokogiri::HTML(response.body).at_css("#ask-ai-results-hint").text.squish)
      .to eq("Opens the AI assistant with your search and your filters.")
  end

  it "is absent on the landing page, where there is no search to carry" do
    stub_solr
    get "/"

    expect(button).to be_nil
  end

  it "does not derive the context while rendering the results page" do
    stub_solr
    expect(Chat::SearchContext).not_to receive(:from_search_params)

    get "/", params: { q: "frogs", search_type: "keyword" }

    expect(response).to have_http_status(:ok)
  end

  it "keeps the carried search when the user flips the navbar to Ask AI" do
    stub_solr
    get "/", params: { q: "frogs", search_type: "keyword" }

    ai_form = Nokogiri::HTML(response.body).at_css(".ai-search-query-form")
    carried = ai_form.css('input[type="hidden"]').to_h { |input| [ input["name"], input["value"] ] }
    expect(carried).to include("search[q]" => "frogs")
  end
end
