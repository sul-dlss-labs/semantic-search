# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::SourceCollection do
  subject(:collection) { described_class.new }

  before do
    allow(Rails.configuration.x.chat).to receive(:max_sources).and_return(10)
    allow(Rails.configuration.x.chat).to receive(:max_source_event_characters).and_return(64_000)
  end

  it "collects sources and merges pages for duplicate URLs" do
    collection.add(
      results: [
        {
          title: "Frog papers",
          url: "http://example.test/frogs",
          matched_chunks: [ { page: 2 } ]
        }
      ],
      passages: [
        {
          document_title: "Frog papers",
          url: "http://example.test/frogs",
          page: "4"
        }
      ]
    )

    selection = collection.for_answer("Frog papers contains the answer.")

    expect(selection.sources).to eq(
      [ { title: "Frog papers", url: "http://example.test/frogs", pages: [ "2", "4" ] } ]
    )
    expect(selection).not_to be_truncated
  end

  it "prioritizes a cited source and reports presentation truncation" do
    allow(Rails.configuration.x.chat).to receive(:max_sources).and_return(1)
    sources = 11.times.map do |index|
      { title: format("Source %02d", index + 1), url: "http://example.test/#{index + 1}" }
    end
    collection.add(results: sources)

    selection = collection.for_answer("The answer appears in Source 11.")

    expect(selection.sources.first).to eq(sources.last)
    expect(selection.emitted_sources).to eq([ sources.last ])
    expect(selection).to be_truncated
  end
end
