# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Search summaries", type: :request do
  let(:token) { SearchSummary.token(query: "frogs", documents: [ SolrDocument.new(title_display_tesi: "Frogs of California") ]) }

  it "renders the summary above results without calling the AI service during page load" do
    solr_response = Blacklight::Solr::Response.new(
      { "response" => { "numFound" => 1, "start" => 0, "docs" => [ { "id" => "abc", "title_display_tesi" => "Frogs" } ] } },
      { rows: 10 }, blacklight_config: CatalogController.blacklight_config
    )
    allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_return(solr_response)
    expect(SearchSummary).not_to receive(:new)

    get "/", params: { q: "frogs", search_type: "keyword" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="ai-summary"')
    expect(response.body.index('data-controller="ai-summary"')).to be < response.body.index('id="sidebar"')
  end

  it "generates a summary from signed search results" do
    summary = instance_double(SearchSummary, call: "These results describe frogs.")
    allow(SearchSummary).to receive(:new).and_return(summary)

    post "/search_summary", params: { token: }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("summary" => "These results describe frogs.")
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(SearchSummary).to have_received(:new).with(hash_including("query" => "frogs"))
  end

  it "rejects tampered search context without calling the model" do
    expect(SearchSummary).not_to receive(:new)
    post "/search_summary", params: { token: "#{token}tampered" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects expired search context" do
    expired_token = SearchSummary.verifier.generate({ query: "frogs" }, expires_at: 1.minute.ago)
    post "/search_summary", params: { token: expired_token }, as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns a useful error when the AI service fails" do
    allow(SearchSummary).to receive(:new).and_raise(Chat::LiteLlmCompletionRequest::RequestError, "private service detail")
    post "/search_summary", params: { token: }, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch("error")).to include("Please try again")
    expect(response.body).not_to include("private service detail")
  end
end
