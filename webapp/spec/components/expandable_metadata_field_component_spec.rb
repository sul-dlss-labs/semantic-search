# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpandableMetadataFieldComponent, type: :component do
  def presenter(key: "abstracts", label: "Abstract", id: "druid:fr576hr0294", values: nil, lines: nil)
    instance_double(
      Blacklight::FieldPresenter,
      document: SolrDocument.new(id: id),
      key: key,
      label: label,
      render: values || [ "A long abstract.", "A second abstract." ],
      render_field?: true,
      layout_component: nil,
      field_config: Blacklight::Configuration::IndexField.new(expandable_lines: lines)
    )
  end

  let(:field) { presenter }
  let(:rendered) { render_inline(described_class.new(field: field)) }

  it "keeps the Blacklight label and value markup" do
    expect(rendered.at_css("dt")["class"]).to eq("blacklight-abstracts col-md-3")
    expect(rendered.css("dd").map { |dd| dd["class"] }).to eq(
      [ "col-md-9 blacklight-abstracts", "offset-md-3 col-md-9 blacklight-abstracts" ]
    )
  end

  it "wraps every value in its own expandable" do
    expect(rendered.css('[data-controller="expandable"]').count).to eq(2)
    expect(rendered.css(".expandable-content").map(&:text)).to eq([ "A long abstract.", "A second abstract." ])
  end

  it "points each toggle at its own content via a unique id" do
    ids = rendered.css(".expandable-content").map { |el| el["id"] }

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

  it "escapes value text" do
    field = presenter(values: [ "<script>alert(1)</script>" ])
    content = render_inline(described_class.new(field: field)).at_css(".expandable-content")

    expect(content.css("script")).to be_empty
    expect(content.text).to eq("<script>alert(1)</script>")
  end

  describe "reuse across fields" do
    it "names the toggle after the field so buttons stay distinguishable" do
      expect(rendered.at_css("button").text.squish).to eq("Show more of abstract")

      other = render_inline(described_class.new(field: presenter(key: "description", label: "Description")))
      expect(other.at_css("button").text.squish).to eq("Show more of description")
    end

    it "namespaces ids by field so two expandable fields on one document cannot collide" do
      other = render_inline(described_class.new(field: presenter(key: "description", label: "Description")))

      expect(other.css(".expandable-content").map { |el| el["id"] })
        .to eq([ "description-druid-fr576hr0294-0", "description-druid-fr576hr0294-1" ])
      expect(other.css(".expandable-content").map { |el| el["id"] } &
             rendered.css(".expandable-content").map { |el| el["id"] }).to be_empty
    end

    it "namespaces ids by document" do
      other = render_inline(described_class.new(field: presenter(id: "druid:bb112zx3193")))

      expect(other.css(".expandable-content").map { |el| el["id"] } &
             rendered.css(".expandable-content").map { |el| el["id"] }).to be_empty
    end
  end

  describe "clamp height" do
    it "defaults to four lines" do
      expect(rendered.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 4")
    end

    it "honours expandable_lines from the field config" do
      other = render_inline(described_class.new(field: presenter(lines: 2)))

      expect(other.at_css(".expandable-content")["style"]).to eq("--expandable-lines: 2")
    end
  end
end
