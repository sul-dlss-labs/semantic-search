require "rails_helper"

RSpec.describe SolrDocument do
  subject(:document) { described_class.new(id: "bb112zx3193", "cocina_ss" => cocina_json) }

  let(:cocina_json) do
    {
      externalIdentifier: "druid:bb112zx3193",
      description: { title: [ { value: "Bugatti Type 51A" } ], note: [] }
    }.to_json
  end

  describe "#cocina_display" do
    it "returns an initialized Cocina record" do
      expect(document.cocina_display).to be_a(CocinaDisplay::CocinaRecord)
      expect(document.cocina_display.display_title).to eq "Bugatti Type 51A"
      expect(document.cocina_display.druid).to eq "druid:bb112zx3193"
    end

    it "memoizes the record" do
      expect(document.cocina_display).to equal document.cocina_display
    end

    context "when the field is multi-valued" do
      subject(:document) { described_class.new(id: "bb112zx3193", "cocina_ss" => [ cocina_json ]) }

      it "uses the first value" do
        expect(document.cocina_display.display_title).to eq "Bugatti Type 51A"
      end
    end

    context "when the document has no Cocina" do
      let(:cocina_json) { nil }

      it { expect(document.cocina_display).to be_nil }
    end
  end

  describe "#abstracts" do
    let(:cocina_json) do
      {
        externalIdentifier: "druid:bb112zx3193",
        description: {
          title: [ { value: "Bugatti Type 51A" } ],
          note: [ { type: "abstract", value: "A racing car." } ]
        }
      }.to_json
    end

    it "returns the abstract note text" do
      expect(document.abstracts).to eq [ "A racing car." ]
    end

    context "when the document has no Cocina" do
      let(:cocina_json) { nil }

      it { expect(document.abstracts).to be_nil }
    end
  end

  describe "#pub_date_str" do
    let(:cocina_json) do
      {
        externalIdentifier: "druid:bb112zx3193",
        description: {
          title: [ { value: "Bugatti Type 51A" } ],
          event: [ { type: "publication", date: [ { value: "1957", encoding: { code: "w3cdtf" } } ] } ]
        }
      }.to_json
    end

    it "returns the publication date" do
      expect(document.pub_date_str).to eq "1957"
    end

    context "when there is only a creation date" do
      let(:cocina_json) do
        {
          externalIdentifier: "druid:bb112zx3193",
          description: {
            title: [ { value: "Bugatti Type 51A" } ],
            event: [ { type: "creation", date: [ { value: "1887", encoding: { code: "w3cdtf" } } ] } ]
          }
        }.to_json
      end

      it "falls back to the creation date" do
        expect(document.pub_date_str).to eq "1887"
      end
    end
  end
end
