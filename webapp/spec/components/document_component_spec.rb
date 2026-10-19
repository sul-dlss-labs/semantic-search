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

  it "forwards filename and page to the embed service, with the page as a zero-based canvas for books" do
    with_request_url("/catalog/fr576hr0294?filename=Kurland%20Transcript.pdf&page=14") do
      element = render_inline(described_class.new(presenter: presenter)).at_css('[data-controller="purl-embed"]')

      expect(element["data-purl-embed-url-value"]).to eq(
        "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/fr576hr0294" \
        "&canvas_index=13&filename=Kurland+Transcript.pdf&page=14"
      )
    end
  end

  it "keeps an explicit canvas_index rather than deriving one from the page" do
    with_request_url("/catalog/fr576hr0294?page=14&canvas_index=2") do
      element = render_inline(described_class.new(presenter: presenter)).at_css('[data-controller="purl-embed"]')

      expect(element["data-purl-embed-url-value"]).to end_with("&canvas_index=2&page=14")
    end
  end

  it "does not derive a canvas from a page that is not a page number" do
    with_request_url("/catalog/fr576hr0294?page=iv") do
      element = render_inline(described_class.new(presenter: presenter)).at_css('[data-controller="purl-embed"]')

      expect(element["data-purl-embed-url-value"]).to end_with("/fr576hr0294&page=iv")
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
