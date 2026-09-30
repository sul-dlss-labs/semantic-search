# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchingExcerpts do
  let(:repository) { instance_double(Blacklight::Solr::Repository) }
  let(:documents) { [ SolrDocument.new(id: "bb191qg8085"), SolrDocument.new(id: "bb205zt9580") ] }
  let(:embedding) { Array.new(GeminiEmbedding::DIMENSIONS, 0.01) }

  let(:payload) do
    {
      "responseHeader" => { "status" => 0 },
      "grouped" => { "_root_" => { "matches" => 488, "groups" => [
        { "groupValue" => "bb191qg8085",
          "doclist" => { "numFound" => 5, "start" => 0, "docs" => [
            { "id" => "bb191qg8085_report_pdf_c4", "chunk_index_i" => 4,
              "filename_ss" => "report.pdf", "page_ss" => "12", "score" => 91.24 }
          ] } }
      ] } },
      "highlighting" => {
        "bb191qg8085_report_pdf_c4" => { "chunk_text_tesi" => [ "…<mark>water</mark> rights…" ] }
      }
    }
  end

  let(:response) do
    Blacklight::Solr::Response.new(payload, {}, blacklight_config: CatalogController.blacklight_config,
                                                document_model: SolrDocument)
  end

  def service(**overrides)
    described_class.new(**{ documents: documents, query: "water rights",
                            repository: repository }.merge(overrides))
  end

  def sent_params
    expect(repository).to have_received(:search)
    @sent_params
  end

  before do
    allow(repository).to receive(:search) { |args| @sent_params = args[:params]; response }
  end

  describe "the Solr request" do
    it "asks for the query terms to be highlighted" do
      service(embedding: embedding).call

      # The highlighter does not see a query expressed in the JSON DSL, so hl.q is required;
      # without it Solr silently returns empty highlights.
      expect(sent_params).to include("hl" => true, "hl.q" => "water rights",
                                     "hl.qparser" => "edismax", "hl.qf" => "chunk_text_tesi",
                                     "hl.encoder" => "html")
    end

    it "excludes the synthetic metadata chunk with must_not rather than a negative filter" do
      service(embedding: embedding).call
      bool = sent_params.dig(:json, :query, :bool)

      # A bare "-field:value" string inside `filter` matches nothing at all in the JSON DSL.
      expect(bool[:must_not]).to eq([ "filename_ss:_metadata_" ])
      expect(bool[:filter]).to all(satisfy { |clause| !clause.start_with?("-") })
    end

    it "asks for one group per document so long documents cannot crowd out short ones" do
      service(embedding: embedding).call

      expect(sent_params).to include("group" => true, "group.field" => "_root_",
                                     "group.limit" => described_class::EXCERPTS_PER_DOCUMENT,
                                     "rows" => documents.length)
    end

    it "restricts the search to the documents on this page" do
      service(embedding: embedding).call
      terms = "{!terms f=_root_}bb191qg8085,bb205zt9580"

      expect(sent_params.dig(:json, :query, :bool, :filter)).to include("doc_type_ssi:child", terms)
    end

    it "mirrors the main search by scoring chunks both ways in hybrid mode" do
      service(embedding: embedding).call
      should = sent_params.dig(:json, :query, :bool, :should)
      vector = should.last.dig(:boost, :query, :vectorSimilarity)

      expect(should.first).to eq({ edismax: { query: "water rights", qf: "chunk_text_tesi" } })
      expect(should.last.dig(:boost, :b)).to eq(SearchBuilder::VECTOR_BOOST)
      expect(vector[:minReturn]).to eq(SearchBuilder::VECTOR_MIN_RETURN)
      # A nested vector query does not inherit the enclosing bool's filters.
      expect(vector[:preFilter]).to include("doc_type_ssi:child", "-filename_ss:_metadata_")
    end

    it "scores chunks lexically only in keyword mode" do
      service(search_type: "keyword", embedding: embedding).call
      should = sent_params.dig(:json, :query, :bool, :should)

      expect(should.length).to eq(1)
      expect(should.first).to have_key(:edismax)
    end

    it "scores chunks semantically only in vector mode" do
      service(search_type: "vector", embedding: embedding).call
      should = sent_params.dig(:json, :query, :bool, :should)

      expect(should.length).to eq(1)
      expect(should.first).to have_key(:boost)
    end
  end

  describe "the excerpts" do
    it "keys them by document and carries the highlighted snippet and its source" do
      expect(service(embedding: embedding).call).to eq(
        "bb191qg8085" => [ {
          chunk_id: "bb191qg8085_report_pdf_c4",
          snippet: "…<mark>water</mark> rights…",
          highlighted: true,
          filename: "report.pdf",
          page: "12",
          chunk_index: 4,
          score: 91.24
        } ]
      )
    end

    it "returns strings the view still has to escape" do
      snippet = service(embedding: embedding).call.values.flatten.first[:snippet]

      expect(snippet).not_to be_html_safe
    end

    it "flags a chunk that matched semantically but contains no query terms" do
      payload["highlighting"]["bb191qg8085_report_pdf_c4"] = { "chunk_text_tesi" => [ "a leading summary" ] }

      expect(service(embedding: embedding).call.values.flatten.first).to include(highlighted: false)
    end

    it "keeps the highlighting when trimming a snippet that runs long" do
      long = "#{'a' * 300}<mark>water</mark>#{'b' * 300}"
      payload["highlighting"]["bb191qg8085_report_pdf_c4"] = { "chunk_text_tesi" => [ long ] }
      snippet = service(embedding: embedding).call.values.flatten.first[:snippet]

      expect(snippet).to include("<mark>water</mark>")
      expect(snippet).to end_with("…")
      expect(snippet.gsub(%r{</?mark>}, "").length).to eq(described_class::MAX_EXCERPT_CHARACTERS + 1)
    end

    it "closes a highlight that the trim cut into" do
      payload["highlighting"]["bb191qg8085_report_pdf_c4"] = {
        "chunk_text_tesi" => [ "#{'a' * 398}<mark>#{'c' * 50}</mark>" ]
      }
      snippet = service(embedding: embedding).call.values.flatten.first[:snippet]

      expect(snippet.scan("<mark>").length).to eq(snippet.scan("</mark>").length)
      expect(snippet).to end_with("</mark>…")
    end

    it "does not split an HTML entity when trimming" do
      payload["highlighting"]["bb191qg8085_report_pdf_c4"] = { "chunk_text_tesi" => [ "&amp;" * 500 ] }
      snippet = service(embedding: embedding).call.values.flatten.first[:snippet]

      expect(snippet).to end_with("&amp;…")
    end

    it "strips markup the highlighter should never have produced" do
      payload["highlighting"]["bb191qg8085_report_pdf_c4"] = { "chunk_text_tesi" => [ "<b>x</b> <mark>y</mark>" ] }

      expect(service(embedding: embedding).call.values.flatten.first[:snippet]).to eq("x y")
    end
  end

  describe "when there is nothing to ask Solr" do
    it "does not search without a query" do
      expect(service(query: nil).call).to eq({})
      expect(repository).not_to have_received(:search)
    end

    it "does not search without documents" do
      expect(service(documents: []).call).to eq({})
      expect(repository).not_to have_received(:search)
    end

    it "falls back to lexical scoring when the embedding is the wrong size" do
      # Sending a wrong-length vector to Solr is a 400.
      service(embedding: [ 0.1, 0.2 ]).call

      expect(sent_params.dig(:json, :query, :bool, :should).length).to eq(1)
    end

    it "does not search in vector mode without a usable embedding" do
      expect(service(search_type: "vector", embedding: nil).call).to eq({})
      expect(repository).not_to have_received(:search)
    end
  end

  describe "when a child chunk is itself a result" do
    let(:child) do
      SolrDocument.new(id: "bb191qg8085_report_pdf_c4", doc_type_ssi: "child",
                       chunk_text_tesi: "rights to <water>", filename_ss: "report.pdf", chunk_index_i: 4)
    end

    it "uses the text it already has and keeps its id out of the parent filter" do
      result = described_class.new(documents: documents + [ child ], query: "water rights",
                                   repository: repository).call

      expect(result[child.id].first).to include(snippet: "rights to &lt;water&gt;", highlighted: false)
      expect(sent_params.dig(:json, :query, :bool, :filter).last).not_to include(child.id)
    end
  end

  describe "when Solr fails" do
    before { allow(repository).to receive(:search).and_raise(Blacklight::Exceptions::InvalidRequest) }

    it "returns no excerpts rather than breaking the results page" do
      allow(Rails.logger).to receive(:warn)

      expect(service(embedding: embedding).call).to eq({})
      expect(Rails.logger).to have_received(:warn).with(/Matching excerpts unavailable/)
    end
  end

  # Every bug found while building this was a Solr syntax bug that a stubbed repository cannot
  # catch, so this exercises the real index. It asserts structure rather than corpus content so
  # that it survives a reindex.
  describe "against the real index" do
    let(:real_repository) { CatalogController.blacklight_config.repository }
    let(:parents) do
      real_repository.search(params: { q: "doc_type_ssi:parent", rows: 10, fl: "id", facet: false }).documents
    end

    it "groups marked excerpts under the documents they came from" do
      result = described_class.new(documents: parents, query: "education", search_type: "keyword").call
      excerpts = result.values.flatten

      expect(result.keys).to all(be_in(parents.map(&:id)))
      expect(result.values.map(&:length)).to all(be <= described_class::EXCERPTS_PER_DOCUMENT)
      expect(excerpts.map { |excerpt| excerpt[:chunk_id] }).to all(include("_c"))
      expect(excerpts).to be_none { |excerpt| excerpt[:chunk_id].include?("__metadata__") }
      expect(excerpts.map { |excerpt| excerpt[:snippet] }).to include(a_string_matching(/<mark>/))
    end

    it "scores chunks semantically when given an embedding" do
      # Borrow a stored vector so the vector path runs without calling out to LiteLLM.
      vector = real_repository.search(
        params: { q: "doc_type_ssi:child", rows: 1, fl: "vector", facet: false }
      ).documents.first["vector"]

      result = described_class.new(documents: parents, query: "education",
                                   search_type: "vector", embedding: vector).call

      expect(result).to be_present
      expect(result.values.flatten).to all(include(:snippet))
    end
  end
end
