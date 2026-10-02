# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::PageComponent, type: :component do
  def search_context(query: "frogs", total: 417)
    Chat::SearchContext.new({ version: 1, query:, total:, page: 1, per_page: 20, page_size: 0, documents: [] })
  end

  it "autostarts a submitted question" do
    rendered = render_inline(described_class.new(question: "frogs in ponds"))

    expect(rendered.at_css(".chat-page")["data-chat-autostart-value"]).to eq("true")
    expect(rendered.at_css("#message").text.strip).to eq("frogs in ponds")
  end

  it "prefills the search context's suggested question without autostarting it" do
    rendered = render_inline(described_class.new(search_context: search_context, search_params: { q: "frogs" }))

    expect(rendered.at_css(".chat-page")["data-chat-autostart-value"]).to eq("false")
    expect(rendered.at_css("#message").text.strip).to eq('What can these results tell me about "frogs"?')
    expect(rendered.css(".alert-warning")).to be_empty
  end

  it "explains a search that arrived but could not be rebuilt, linking back to it" do
    rendered = render_inline(described_class.new(search_params: { q: "frogs" }))

    expect(rendered.at_css(".alert-warning").text).to include("no longer available")
    expect(rendered.at_css(".alert-warning a")["href"]).to eq("/catalog?q=frogs")
    expect(rendered.css(".chat-context")).to be_empty
  end

  describe "#greeting" do
    it "greets a conversation without a search context" do
      expect(described_class.new.greeting).to eq("What would you like to learn from the collections?")
    end

    it "names the query a search context carries" do
      expect(described_class.new(search_context: search_context).greeting)
        .to eq('I can see the results from your search for "frogs". What would you like to know about them?')
    end

    it "still offers to help when the search matched nothing" do
      expect(described_class.new(search_context: search_context(total: 0)).greeting)
        .to start_with("That search did not match anything")
    end

    it "does not name a query when the search had none" do
      expect(described_class.new(search_context: search_context(query: nil)).greeting)
        .to eq("I can see the results from your search. What would you like to know about them?")
    end
  end
end
