# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::SearchContext do
  let(:documents) do
    3.times.map do |index|
      {
        id: "doc#{index}",
        title_display_tesi: "Interview number #{index}",
        author_person_ssim: [ "Jones, Mary", "Smith, Ann", "Lee, Sam", "Dropped, Author" ],
        collection_title_ss: "Stanford Oral History Project",
        creation_date_dtsi: "1974-03-02T00:00:00Z"
      }
    end
  end

  def stub_solr(docs: documents, total: 417)
    response = Blacklight::Solr::Response.new(
      { "response" => { "numFound" => total, "start" => 0, "docs" => docs } },
      { rows: 20 }, blacklight_config: CatalogController.blacklight_config
    )
    allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_return(response)
  end

  describe ".from_search_params" do
    it "carries the query, paging, and the documents on that page" do
      stub_solr
      context = described_class.from_search_params({ q: "band auditions", page: "2", per_page: "20" })

      expect(context.query).to eq("band auditions")
      expect(context.total).to eq(417)
      expect(context.page).to eq(2)
      expect(context.per_page).to eq(20)
      expect(context.page_size).to eq(3)
      expect(context.first_item).to eq(21)
      expect(context.last_item).to eq(23)
      expect(context).not_to be_zero_results
    end

    it "re-derives the search strategy that CatalogController's before_action would have set" do
      stub_solr
      allow(CatalogSearchClassifier).to receive(:new).with("band auditions")
        .and_return(instance_double(CatalogSearchClassifier, call: "vector"))

      expect(described_class.from_search_params({ q: "band auditions" }).search_type).to eq("vector")
    end

    it "bounds the carried documents and reports the page it trimmed" do
      allow(Rails.configuration.x.chat).to receive(:max_search_context_documents).and_return(2)
      stub_solr

      context = described_class.from_search_params({ q: "band auditions" })

      expect(context.documents.length).to eq(2)
      expect(context.page_size).to eq(3)
      expect(context).to be_truncated
    end

    it "flattens and bounds document metadata for the prompt" do
      stub_solr(docs: [ documents.first.merge(title_display_tesi: "A\ntitle\twith  whitespace") ])

      document = described_class.from_search_params({ q: "band auditions" }).documents.first

      expect(document[:title]).to eq("A title with whitespace")
      expect(document[:authors]).to eq([ "Jones, Mary", "Smith, Ann", "Lee, Sam" ])
      expect(document[:collection]).to eq("Stanford Oral History Project")
      expect(document[:date]).to eq("1974")
    end

    it "builds document URLs identically to the chat tools, so sources dedupe" do
      stub_solr
      controller = ChatsController.new
      controller.request = ActionDispatch::TestRequest.create

      carried = described_class.from_search_params({ q: "band auditions" }, controller:).documents
      expected = SemanticSearchMcp::CatalogResults.record_url(controller, "doc0")

      expect(carried.first[:url]).to eq(expected)
    end

    it "keeps a zero-result search as context rather than discarding it" do
      stub_solr(docs: [], total: 0)
      context = described_class.from_search_params({ q: "nothing here" })

      expect(context).to be_zero_results
      expect(context.documents).to be_empty
      expect(context.first_item).to eq(0)
    end

    it "returns nil when there is no search to carry" do
      expect(described_class.from_search_params({})).to be_nil
      expect(described_class.from_search_params(nil)).to be_nil
      expect(described_class.from_search_params({ page: "2" })).to be_nil
    end

    it "returns nil instead of raising when the search cannot run" do
      allow_any_instance_of(Blacklight::Solr::Repository).to receive(:search).and_raise(StandardError, "solr down")

      expect(described_class.from_search_params({ q: "band auditions" })).to be_nil
    end
  end

  describe "filters" do
    it "maps active facets to their catalog_search_tool filter keys" do
      stub_solr
      context = described_class.from_search_params(
        { q: "band", f: { "collection_title_ss" => [ "Stanford Oral History Project" ],
                          "author_other_ssim" => [ "Stanford Historical Society" ] } }
      )

      expect(context.filters).to contain_exactly(
        { label: "Organization (as author)", values: [ "Stanford Historical Society" ],
          tool_key: "organization_as_author" },
        { label: "Collection", values: [ "Stanford Oral History Project" ], tool_key: "collection" }
      )
      expect(context.tool_filters).to eq(
        "organization_as_author" => "Stanford Historical Society",
        "collection" => "Stanford Oral History Project"
      )
    end

    it "displays a query facet but does not claim a tool filter for it" do
      stub_solr
      context = described_class.from_search_params({ q: "band", f: { "child_count_i" => [ "many" ] } })

      expect(context.filters).to eq(
        [ { label: "Text chunks", values: [ "Present" ], tool_key: nil } ]
      )
      expect(context.tool_filters).to be_empty
    end

    it "sends only the first value of a multi-select facet, which is all the tool accepts" do
      stub_solr
      context = described_class.from_search_params({ q: "band", f: { "topic_ssim" => %w[Music Sports] } })

      expect(context.filters.first[:values]).to eq(%w[Music Sports])
      expect(context.tool_filters).to eq("topic" => "Music")
    end
  end

  describe "tokens" do
    it "round-trips the carried context" do
      stub_solr
      original = described_class.from_search_params({ q: "band auditions", page: "2" })

      restored = described_class.from_token(original.token)

      expect(restored.query).to eq("band auditions")
      expect(restored.page).to eq(2)
      expect(restored.total).to eq(417)
      expect(restored.documents).to eq(original.documents)
      expect(restored.tool_filters).to eq(original.tool_filters)
    end

    it "refuses a missing, tampered, or expired token without raising" do
      stub_solr
      token = described_class.from_search_params({ q: "band auditions" }).token

      expect(described_class.from_token(nil)).to be_nil
      expect(described_class.from_token("")).to be_nil
      expect(described_class.from_token("#{token}tampered")).to be_nil
      expect(described_class.from_token(described_class.verifier.generate({ version: 1 }, expires_at: 1.minute.ago)))
        .to be_nil
    end

    it "refuses a validly signed payload from another version" do
      expect(described_class.from_token(described_class.verifier.generate({ version: 99 }))).to be_nil
    end
  end

  describe "results the user removed" do
    def restored(excluded_ids)
      stub_solr
      described_class.from_token(
        described_class.from_search_params({ q: "band auditions" }).token, excluded_ids:
      )
    end

    it "drops the named documents from the carried page" do
      context = restored([ "doc1" ])

      expect(context.documents.map { |document| document[:id] }).to eq([ "doc0", "doc2" ])
      expect(context.carried_documents.length).to eq(3)
      expect(context.removed_count).to eq(1)
    end

    it "keeps the removed documents out of the citation seed" do
      expect(restored([ "doc0", "doc2" ]).seed_sources).to eq(
        results: [ { title: "Interview number 1", url: "/catalog/doc1" } ]
      )
    end

    # A removal is the user editing the context, not us running out of room, and the prompt words
    # those two differently.
    it "does not read a removal as the carry having been truncated" do
      context = restored([ "doc1" ])

      expect(context).not_to be_truncated
      expect(context.page_size).to eq(3)
    end

    it "ignores ids that were never carried, and non-string junk" do
      context = restored([ "doc9", 42, { "id" => "doc0" }, nil ])

      expect(context.documents.length).to eq(3)
      expect(context.removed_count).to eq(0)
    end

    it "treats a missing exclusion list as nothing removed" do
      expect(restored(nil).documents.length).to eq(3)
      expect(restored(nil).removed_count).to eq(0)
    end
  end

  describe "#seed_sources" do
    it "exposes carried documents in the shape SourceCollection accepts" do
      stub_solr(docs: [ documents.first ])
      context = described_class.from_search_params({ q: "band auditions" })

      expect(context.seed_sources).to eq(
        results: [ { title: "Interview number 0", url: "/catalog/doc0" } ]
      )
    end
  end

  describe "#suggested_question" do
    it "names the query so the prefilled question reads like the user's own" do
      stub_solr
      context = described_class.from_search_params({ q: "band auditions" })

      expect(context.suggested_question).to eq('What can these results tell me about "band auditions"?')
    end

    it "falls back to a generic question for a facet-only browse" do
      stub_solr
      context = described_class.from_search_params({ f: { "topic_ssim" => [ "Music" ] } })

      expect(context.suggested_question).to eq("What is in these results?")
    end

    it "points at the topic rather than absent results when the search found nothing" do
      stub_solr(docs: [], total: 0)
      context = described_class.from_search_params({ q: "band auditions" })

      expect(context.suggested_question).to eq('What can you find about "band auditions"?')
    end

    it "does not double the quotes on a quoted-phrase search" do
      stub_solr
      context = described_class.from_search_params({ q: '"band auditions"' })

      expect(context.suggested_question).to eq('What can these results tell me about "band auditions"?')
    end
  end
end
