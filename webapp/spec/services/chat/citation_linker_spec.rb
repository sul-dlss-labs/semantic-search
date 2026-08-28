# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::CitationLinker do
  subject(:linker) { described_class.new(sources:) }

  let(:sources) do
    [
      {
        title: "Stanford report. Volume 36, 2003-2004",
        url: "https://example.test/catalog/vm857hw3603",
        pages: [ "571" ]
      }
    ]
  end

  it "links a verified bare source title and page" do
    answer = "Kathleen Namphy died after the fall Stanford report. Volume 36, 2003-2004, p. 571."

    expect(linker.call(answer)).to eq(
      "Kathleen Namphy died after the fall " \
      "[Stanford report. Volume 36, 2003-2004, p. 571](<https://example.test/catalog/vm857hw3603>)."
    )
  end

  it "preserves an existing Markdown citation" do
    answer = "See [Stanford report. Volume 36, 2003-2004, p. 571](https://example.test/catalog/vm857hw3603)."

    expect(linker.call(answer)).to eq(answer)
  end

  it "does not link titles that were not returned as verified sources" do
    answer = "See A different report, p. 12."

    expect(linker.call(answer)).to eq(answer)
  end
end
