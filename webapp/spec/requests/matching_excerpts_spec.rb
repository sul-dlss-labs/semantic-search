# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Matching excerpts", type: :request do
  # Title-like queries classify as keyword searches, which keeps LiteLLM out of the request.
  let(:query) { "Water Rights" }
  let(:ids) { %w[bb191qg8085 bb205zt9580] }
  let(:documents) do
    Blacklight::Solr::Response.new(
      { "response" => { "numFound" => 2, "start" => 0, "docs" => [
        { "id" => "bb191qg8085", "doc_type_ssi" => "parent", "title_tsim" => [ "Water Rights" ] },
        { "id" => "bb205zt9580", "doc_type_ssi" => "parent", "title_tsim" => [ "Riparian Law" ] }
      ] } },
      {}, blacklight_config: CatalogController.blacklight_config, document_model: SolrDocument
    )
  end
  let(:excerpts) do
    {
      "bb191qg8085" => [ { chunk_id: "bb191qg8085_report_pdf_c4", filename: "report.pdf", page: "12",
                           snippet: "the <mark>water</mark> <script>alert(1)</script> rights" } ]
    }
  end
  let(:service) { instance_double(MatchingExcerpts, call: excerpts) }

  def streams
    Nokogiri::HTML.fragment(response.body).css("turbo-stream")
  end

  before do
    allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_return(documents)
    allow(MatchingExcerpts).to receive(:new).and_return(service)
    allow(GeminiEmbedding).to receive(:query_embedding)
  end

  it "fills in the placeholder of each result that has matching text and removes the rest" do
    # Turbo frame requests accept HTML; the stream content type is what makes Turbo apply it.
    get matching_excerpts_path(q: query, ids: ids), headers: { "Accept" => "text/html", "Turbo-Frame" => "matching-excerpts" }

    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(streams.map { |stream| [ stream["action"], stream["target"] ] }).to eq([
      [ "remove", "matching-excerpts-label-bb191qg8085" ],
      [ "replace", "matching-excerpts-slot-bb191qg8085" ],
      [ "remove", "matching-excerpts-label-bb205zt9580" ],
      [ "remove", "matching-excerpts-slot-bb205zt9580" ]
    ])

    field = streams.find { |stream| stream["action"] == "replace" }.at_css("template")
    expect(field.at_css("dt").text.strip).to eq("Matching text:")
    expect(field.css(".matching-excerpt mark").map(&:text)).to eq(%w[water])
    expect(field.css("script")).to be_empty
    expect(field.at_css(".matching-excerpt-source a")["href"])
      .to eq("/catalog/bb191qg8085?canvas_index=11")
  end

  it "searches as the results page did, without embedding a keyword query" do
    get matching_excerpts_path(q: query, ids: ids)

    expect(MatchingExcerpts).to have_received(:new)
      .with(documents: documents.documents, query: query, search_type: "keyword", embedding: nil)
    expect(documents.documents.map(&:id)).to eq(ids)
    expect(GeminiEmbedding).not_to have_received(:query_embedding)
  end

  it "reuses the cached query embedding for semantic searches" do
    embedding = Array.new(GeminiEmbedding::DIMENSIONS, 0.01)
    allow(GeminiEmbedding).to receive(:query_embedding).and_return(embedding)

    get matching_excerpts_path(q: "frogs", ids: ids)

    expect(GeminiEmbedding).to have_received(:query_embedding).with("frogs")
    expect(MatchingExcerpts).to have_received(:new).with(hash_including(search_type: "hybrid", embedding: embedding))
  end

  it "still finds keyword excerpts when the embedding is unavailable" do
    allow(GeminiEmbedding).to receive(:query_embedding).and_raise("LiteLLM is down")

    get matching_excerpts_path(q: "frogs", ids: ids)

    expect(response).to have_http_status(:success)
    expect(MatchingExcerpts).to have_received(:new).with(hash_including(search_type: "hybrid", embedding: nil))
  end

  it "removes every placeholder when nothing matched" do
    allow(service).to receive(:call).and_return({})

    get matching_excerpts_path(q: query, ids: ids)

    expect(streams.pluck("action")).to eq(%w[remove remove remove remove])
  end

  it "removes the placeholders rather than leave them loading when the lookup fails" do
    allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_raise(Blacklight::Exceptions::InvalidRequest)

    get matching_excerpts_path(q: query, ids: ids)

    expect(response).to have_http_status(:success)
    expect(streams.map { |stream| [ stream["action"], stream["target"] ] }).to eq([
      [ "remove", "matching-excerpts-label-bb191qg8085" ], [ "remove", "matching-excerpts-slot-bb191qg8085" ],
      [ "remove", "matching-excerpts-label-bb205zt9580" ], [ "remove", "matching-excerpts-slot-bb205zt9580" ]
    ])
  end

  it "removes the placeholder of a result that is no longer in the index" do
    get matching_excerpts_path(q: query, ids: ids + [ "zz999zz9999" ])

    expect(streams.to_a.last(2).map { |stream| [ stream["action"], stream["target"] ] }).to eq([
      [ "remove", "matching-excerpts-label-zz999zz9999" ], [ "remove", "matching-excerpts-slot-zz999zz9999" ]
    ])
  end
end
