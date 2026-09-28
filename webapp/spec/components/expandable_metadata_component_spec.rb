# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpandableMetadataComponent, type: :component do
  def presenter(lines: nil)
    instance_double(
      Blacklight::FieldPresenter,
      document: SolrDocument.new(id: "druid:fr576hr0294"),
      key: "abstracts",
      label: "Abstract",
      render: [ "A long abstract.", "A second abstract." ],
      render_field?: true,
      layout_component: nil,
      field_config: Blacklight::Configuration::IndexField.new(expandable_lines: lines)
    )
  end

  let(:rendered) { render_inline(described_class.new(field: presenter)) }

  it "wraps every value in its own expandable, keyed by field, document and index" do
    ids = rendered.css(".expandable-content").map { |el| el["id"] }

    expect(rendered.css('[data-controller="expandable"]').count).to eq(2)
    expect(ids).to eq([ "abstracts-druid-fr576hr0294-0", "abstracts-druid-fr576hr0294-1" ])
    expect(rendered.css("button").map { |button| button["aria-controls"] }).to eq(ids)
  end

  it "starts collapsed with the toggle hidden until JS measures the overflow" do
    rendered.css("button").each do |button|
      expect(button["aria-expanded"]).to eq("false")
      expect(button["hidden"]).not_to be_nil
    end

    expect(rendered.css(".expandable-content.is-expanded")).to be_empty
  end

  it "names the toggle after the field so buttons stay distinguishable" do
    expect(rendered.at_css("button").text.squish).to eq("Show more of abstract")
  end

  it "clamps to expandable_lines from the field config, defaulting to three lines" do
    expect(rendered.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 3")

    other = render_inline(described_class.new(field: presenter(lines: 2)))
    expect(other.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 2")
  end
end
