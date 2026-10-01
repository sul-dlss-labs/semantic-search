# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchingExcerptsComponent, type: :component do
  def presenter(values: excerpts, lines: nil,
                document: SolrDocument.new(id: "fr576hr0294", title_display_tesi: "Frogs of the Valley"))
    instance_double(
      Blacklight::FieldPresenter,
      document: document,
      key: "matching_excerpts",
      label: "Matching text",
      values: values,
      render_field?: true,
      layout_component: nil,
      field_config: Blacklight::Configuration::IndexField.new(expandable_lines: lines)
    )
  end

  let(:excerpts) do
    [
      { chunk_id: "a_c1", snippet: "the <mark>frogs</mark> of the valley", highlighted: true,
        filename: "chapter-01.pdf", page: "12", chunk_index: 3, score: 0.91 },
      { chunk_id: "a_c7", snippet: "more about amphibians", highlighted: false,
        filename: "chapter-02.pdf", chunk_index: 7, score: 0.62 }
    ]
  end

  let(:rendered) { render_inline(described_class.new(field: presenter)) }

  it "renders the excerpts as one metadata value so the whole list shares a single toggle" do
    expect(rendered.at_css("dt").text).to include("Matching text")
    expect(rendered.css("dd").count).to eq(1)
    expect(rendered.css("dd .matching-excerpt").count).to eq(2)
    expect(rendered.css('[data-controller="expandable"]').count).to eq(1)
  end

  it "attributes each excerpt to its source, omitting parts the index did not supply" do
    sources = rendered.css(".matching-excerpt-source").map { |node| node.text.strip }

    expect(sources).to eq([ "chapter-01.pdf · page 12", "chapter-02.pdf" ])
  end

  it "links each source to the record's page, opening the viewer at the matching page like chat citations" do
    links = rendered.css(".matching-excerpt-source a")

    expect(links.map(&:text)).to eq([ "chapter-01.pdf · page 12", "chapter-02.pdf" ])
    expect(links.pluck("href")).to eq([ "/catalog/fr576hr0294?canvas_index=11", "/catalog/fr576hr0294" ])
  end

  it "links to the record without a canvas when the page is not a page number" do
    named = [ { chunk_id: "a_c1", snippet: "text", filename: "Front matter.pdf", page: "iv" },
              { chunk_id: "a_c2", snippet: "text", filename: "cover.pdf", page: "0" } ]
    output = render_inline(described_class.new(field: presenter(values: named)))

    expect(output.css(".matching-excerpt-source a").pluck("href")).to eq([ "/catalog/fr576hr0294" ] * 2)
  end

  it "links a matching chunk that is itself a result to its parent record" do
    child = presenter(document: SolrDocument.new(id: "fr576hr0294_chapter-01_pdf_c3"))
    output = render_inline(described_class.new(field: child))

    expect(output.at_css(".matching-excerpt-source a")["href"]).to eq("/catalog/fr576hr0294?canvas_index=11")
  end

  it "does not render a source line when the index supplied neither file nor page" do
    output = render_inline(described_class.new(field: presenter(values: [ { chunk_id: "a_c1", snippet: "text" } ])))

    expect(output.css(".matching-excerpt-source")).to be_empty
  end

  it "does not expose the relevance score or chunk index" do
    expect(rendered.to_html).not_to include("0.91")
    expect(rendered.text).not_to include("chunk")
  end

  it "keeps Solr's highlighting" do
    expect(rendered.at_css("blockquote mark").text).to eq("frogs")
  end

  it "escapes untrusted document text rather than trusting the index" do
    hostile = [ { chunk_id: "a_c1", snippet: "<script>alert(1)</script> & <b>bold</b>" } ]
    output = render_inline(described_class.new(field: presenter(values: hostile)))

    expect(output.css("script")).to be_empty
    expect(output.css("b")).to be_empty
    expect(output.at_css("blockquote").text).to include("alert(1)")
    expect(output.at_css("blockquote").text).to include("&")
  end

  it "starts collapsed with the toggle hidden until JS measures the overflow" do
    button = rendered.at_css("button.expandable-toggle")

    expect(button["aria-expanded"]).to eq("false")
    expect(button["hidden"]).not_to be_nil
    expect(button["aria-controls"]).to eq(rendered.at_css(".expandable-content")["id"])
    expect(rendered.css(".expandable-content.is-expanded")).to be_empty
  end

  it "names the toggle after the document so buttons stay distinguishable across results" do
    expect(rendered.at_css("button").text.squish).to eq("Show more matching text for Frogs of the Valley")
    expect(rendered.at_css(".expandable-content")["id"]).to eq("matching-excerpts-fr576hr0294")
  end

  it "clamps to expandable_lines from the field config, defaulting to six lines" do
    expect(rendered.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 6")

    other = render_inline(described_class.new(field: presenter(lines: 2)))
    expect(other.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 2")
  end

  it "renders the label and a loading skeleton while the excerpts are loading" do
    output = render_inline(described_class.new(field: presenter(values: described_class::PENDING)))

    expect(output.at_css("dt")["id"]).to eq("matching-excerpts-label-fr576hr0294")
    expect(output.at_css("dt").text).to include("Matching text")
    expect(output.at_css("dd")["id"]).to eq("matching-excerpts-slot-fr576hr0294")
    expect(output.at_css("dd")["aria-busy"]).to eq("true")
    expect(output.at_css("dd .visually-hidden").text).to eq("Loading matching text…")
    expect(output.css("dd .skeleton.placeholder-glow .placeholder").count).to eq(3)
    expect(output.css(".matching-excerpt")).to be_empty
  end

  it "mirrors the classes of Blacklight's field layout so the placeholder lines up" do
    pending_output = render_inline(described_class.new(field: presenter(values: described_class::PENDING)))
    loaded = render_inline(described_class.new(field: presenter))

    expect(pending_output.at_css("dt")["class"].split).to include(*loaded.at_css("dt")["class"].split)
    expect(pending_output.at_css("dd")["class"].split).to include(*loaded.at_css("dd")["class"].split)
  end

  it "renders nothing when the document has no matching excerpts" do
    expect(render_inline(described_class.new(field: presenter(values: []))).to_html).to be_blank
  end
end
