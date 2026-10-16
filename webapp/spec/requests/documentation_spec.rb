# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Documentation", type: :request do
  describe "GET /documentation" do
    it "explains search modes and Ask AI" do
      get "/documentation"

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML(response.body)
      headings = page.css(".documentation-content h2, .documentation-content h3").map { |heading| heading.text.squish }
      expect(headings).to include(
        "How a search mode is chosen", "Keyword search", "Semantic search", "Hybrid search", "Ask AI", "Limitations"
      )
      expect(response.body).to include("Reciprocal Rank Fusion")
      expect(page.at_css('nav.documentation-toc a[href="#overview"]')).to be_present
      expect(page.at_css('a.nav-link[href="/documentation"][aria-current="page"]')).to be_present
    end
  end
end
