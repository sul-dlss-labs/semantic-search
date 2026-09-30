# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchingExcerptsComponent, type: :component do
  def presenter(values: excerpts, lines: nil)
    instance_double(
      Blacklight::FieldPresenter,
      document: SolrDocument.new(id: "druid:fr576hr0294", title_display_tesi: "Frogs of the Valley"),
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

    expect(sources).to eq([ "chapter-01.pdf · page 12 · chunk 3", "chapter-02.pdf · chunk 7" ])
  end

  it "does not expose the relevance score" do
    expect(rendered.to_html).not_to include("0.91")
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
    expect(rendered.at_css(".expandable-content")["id"]).to eq("matching-excerpts-druid-fr576hr0294")
  end

  it "clamps to expandable_lines from the field config, defaulting to six lines" do
    expect(rendered.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 6")

    other = render_inline(described_class.new(field: presenter(lines: 2)))
    expect(other.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 2")
  end

  it "renders nothing when the document has no matching excerpts" do
    expect(render_inline(described_class.new(field: presenter(values: []))).to_html).to be_blank
  end
end
