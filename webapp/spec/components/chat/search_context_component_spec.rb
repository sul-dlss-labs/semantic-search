# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::SearchContextComponent, type: :component do
  let(:search_context) do
    Chat::SearchContext.new(
      { version: 1, query: "frogs", total: 417, page: 1, per_page: 20, page_size: 2,
        filters: [ { label: "Collection", values: [ "Frog Oral Histories" ] } ],
        documents: [ { id: "bb112zx3193", title: "Frog interview", collection: "Frog Oral Histories" } ],
        search_params: { q: "frogs" } }
    )
  end

  let(:rendered) { render_inline(described_class.new(search_context:)) }

  it "summarizes the search, its filters, and the results carried over" do
    expect(rendered.at_css(".chat-context-summary").text.squish).to include("frogs", "417 results", "showing 1–2")
    expect(rendered.at_css(".chat-context-filter").text.squish).to include("Collection:", "Frog Oral Histories")
    expect(rendered.at_css(".chat-context-list a").text).to eq("Frog interview")
    expect(rendered.at_css(".chat-context-back")["href"]).to eq("/catalog?q=frogs")
  end

  it "notes when fewer results were carried than the page showed" do
    expect(rendered.text.squish).to include("Your page showed 2 results; the first 1 were carried")
  end

  it "renders nothing without a search context" do
    expect(render_inline(described_class.new(search_context: nil)).to_html).to be_blank
  end
end
