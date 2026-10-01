# frozen_string_literal: true

require "rails_helper"

RSpec.describe "catalog/_ai_summary", type: :view do
  let(:cocina_json) do
    {
      externalIdentifier: "druid:bb112zx3193",
      description: { title: [ { value: "Frogs" } ], note: [] }
    }.to_json
  end
  let(:document) { SolrDocument.new(title_display_tesi: "Frogs", cocina_ss: cocina_json) }

  before { controller.params[:q] = "frogs" }

  it "captions the summary with the number of results on the page" do
    render partial: "catalog/ai_summary", locals: { documents: [ document ] * 50 }
    expect(rendered).to include("AI-generated summary of the 50 results on this page")
  end

  it "keeps the caption grammatical for a single result" do
    render partial: "catalog/ai_summary", locals: { documents: [ document ] }
    expect(rendered).to include("AI-generated summary of the 1 result on this page")
  end

  it "renders skeleton bars that screen readers skip" do
    render partial: "catalog/ai_summary", locals: { documents: [ document ] }
    bars = Nokogiri::HTML(rendered).css(".skeleton.placeholder-glow[aria-hidden='true'] .placeholder")
    expect(bars.size).to eq(5)
  end

  it "shows the loading caption in the row the toggle will occupy" do
    render partial: "catalog/ai_summary", locals: { documents: [ document ] }
    footer = Nokogiri::HTML(rendered).at_css(".ai-summary-footer")
    caption = footer.at_css("p[role='status']")
    expect(caption.text).to eq("Loading AI summary…")
    expect(caption["class"]).not_to include("visually-hidden")
    expect(footer.at_css("button.ai-summary-toggle")["class"]).to include("invisible")
  end
end
