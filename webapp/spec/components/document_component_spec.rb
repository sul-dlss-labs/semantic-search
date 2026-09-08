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

  it "forwards a highlight search alongside the canvas index" do
    with_request_url("/catalog/fr576hr0294?canvas_index=7&search=%22calendar+of+campus%22") do
      expect(embed_url).to eq(
        "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/fr576hr0294" \
        "&canvas_index=7&search=%22calendar%20of%20campus%22"
      )
    end
  end

  it "forwards a canvas id, which targets a page more precisely than its index" do
    canvas = "https://purl.stanford.edu/fr576hr0294/iiif/canvas/one"

    with_request_url("/catalog/fr576hr0294?canvas_id=#{CGI.escape(canvas)}&search=frogs") do
      expect(embed_url).to eq(
        "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/fr576hr0294" \
        "&canvas_id=#{ERB::Util.url_encode(canvas)}&search=frogs"
      )
    end
  end

  it "omits a canvas index that is not a page number" do
    with_request_url("/catalog/fr576hr0294?canvas_index=nonsense") do
      expect(embed_url).not_to include("canvas_index")
    end
  end

  it "omits a canvas id that is not an absolute HTTP URL" do
    with_request_url("/catalog/fr576hr0294?canvas_id=javascript%3Aalert(1)") do
      expect(embed_url).not_to include("canvas_id")
    end
  end

  it "omits a search that is blank or implausibly long" do
    with_request_url("/catalog/fr576hr0294?search=%20") do
      expect(embed_url).not_to include("search")
    end

    with_request_url("/catalog/fr576hr0294?search=#{'x' * 200}") do
      expect(embed_url).not_to include("search")
    end
  end

  def embed_url
    render_inline(described_class.new(presenter: presenter))
      .at_css('[data-controller="purl-embed"]')["data-purl-embed-url-value"]
  end
end
