# frozen_string_literal: true

require "rails_helper"

RSpec.describe "catalog/_search_details", type: :view do
  it "shows the strategy and how the query embedding was obtained" do
    controller.params[:search_type] = "hybrid"
    Current.embedding_lookup = { duration_ms: 312.4, cached: false }

    render partial: "catalog/search_details"

    expect(rendered.squish).to include("Search strategy: hybrid · Query embedding: 312 ms (not cached)")
  end

  it "notes a cached embedding" do
    controller.params[:search_type] = "vector"
    Current.embedding_lookup = { duration_ms: 2.0, cached: true }

    render partial: "catalog/search_details"

    expect(rendered.squish).to include("Query embedding: 2 ms (cached)")
  end

  it "leaves out the embedding when none was used" do
    controller.params[:search_type] = "keyword"

    render partial: "catalog/search_details"

    expect(rendered.squish).to include("Search strategy: keyword")
    expect(rendered).not_to include("Query embedding")
  end
end
