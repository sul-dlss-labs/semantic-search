# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentComponent, type: :component do
  let(:document) { SolrDocument.new(id: "fr576hr0294") }
  let(:presenter) { instance_double(Blacklight::DocumentPresenter, document: document) }

  it "forwards canvas_index to the embed service" do
    with_request_url("/catalog/fr576hr0294?canvas_index=7") do
      element = render_inline(described_class.new(presenter: presenter)).at_css('[data-controller="purl-embed"]')

      expect(element["data-purl-embed-url-value"]).to eq(
        "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/fr576hr0294&canvas_index=7"
      )
    end
  end

  it "omits canvas_index when it is not provided" do
    with_request_url("/catalog/fr576hr0294") do
      element = render_inline(described_class.new(presenter: presenter)).at_css('[data-controller="purl-embed"]')

      expect(element["data-purl-embed-url-value"]).to eq(
        "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/fr576hr0294"
      )
    end
  end
end
