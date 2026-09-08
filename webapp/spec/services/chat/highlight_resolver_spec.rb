# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::HighlightResolver do
  subject(:resolver) { described_class.new(source_collection:, client:) }

  let(:client) { instance_double(Chat::ContentSearchClient) }
  let(:url) { "http://example.test/catalog/fr576hr0294" }
  let(:canvas) { "https://purl.stanford.edu/fr576hr0294/iiif/canvas/one" }
  let(:answer) { "The center opened that spring (Cantor Arts Center, p. 124)." }

  let(:source_collection) do
    Chat::SourceCollection.new.tap do |collection|
      collection.add(
        passages: [
          {
            document_id: "fr576hr0294",
            document_title: "Cantor Arts Center",
            url: url,
            page: "124",
            text: "special exhibitions are on view every Wednesday\nand the center opened that spring season\n"
          }
        ]
      )
    end
  end

  let(:sources) { source_collection.for_answer(answer).emitted_sources }

  before do
    allow(Rails.configuration.x.chat).to receive(:highlight_verification).and_return(true)
    allow(Rails.configuration.x.chat).to receive(:highlight_attempts_per_page).and_return(1)
    allow(Rails.configuration.x.chat).to receive(:max_sources).and_return(10)
    allow(Rails.configuration.x.chat).to receive(:max_source_event_characters).and_return(64_000)
  end

  it "keeps a confirmed phrase and its canvas when the phrase occurs on exactly one canvas" do
    allow(client).to receive(:canvas_ids).and_return([ canvas ])

    highlights = resolver.call(sources, answer)

    expect(highlights[url]["124"]).to include(canvas_id: canvas)
    expect(highlights[url]["124"][:phrase]).to be_present
  end

  it "queries the phrase against the object's own druid" do
    allow(client).to receive(:canvas_ids).and_return([ canvas ])

    resolver.call(sources, answer)

    expect(client).to have_received(:canvas_ids).with(hash_including(druid: "fr576hr0294"))
  end

  it "keeps the phrase but no canvas when it occurs on several canvases" do
    allow(client).to receive(:canvas_ids).and_return([ canvas, "#{canvas}-two" ])

    highlights = resolver.call(sources, answer)

    expect(highlights[url]["124"]).not_to have_key(:canvas_id)
    expect(highlights[url]["124"][:phrase]).to be_present
  end

  it "drops the highlight when the phrase matches nothing" do
    allow(client).to receive(:canvas_ids).and_return([])

    expect(resolver.call(sources, answer)).to eq({})
  end

  it "drops the highlight when the service could not be reached" do
    allow(client).to receive(:canvas_ids).and_return(nil)

    expect(resolver.call(sources, answer)).to eq({})
  end

  it "makes one lookup per cited page" do
    allow(client).to receive(:canvas_ids).and_return([ canvas ])

    resolver.call(sources, answer)

    expect(client).to have_received(:canvas_ids).once
  end

  it "does nothing when highlight verification is disabled" do
    allow(Rails.configuration.x.chat).to receive(:highlight_verification).and_return(false)
    allow(client).to receive(:canvas_ids)

    expect(resolver.call(sources, answer)).to eq({})
    expect(client).not_to have_received(:canvas_ids)
  end

  it "stops looking things up once the request budget is spent" do
    stub_const("#{described_class}::MAX_REQUESTS", 1)
    allow(client).to receive(:canvas_ids).and_return([])
    source_collection.add(
      passages: [
        { document_id: "fr576hr0294", document_title: "Cantor Arts Center", url:, page: "200",
          text: "another page of exhibition listings and events\n" }
      ]
    )

    resolver.call(source_collection.for_answer(answer).emitted_sources, answer)

    expect(client).to have_received(:canvas_ids).once
  end

  it "tries a shorter candidate when the first one matches nothing" do
    allow(Rails.configuration.x.chat).to receive(:highlight_attempts_per_page).and_return(3)
    allow(client).to receive(:canvas_ids).and_return(nil, [], [ canvas ])

    highlights = resolver.call(sources, answer)

    expect(client).to have_received(:canvas_ids).exactly(3).times
    expect(highlights[url]["124"]).to include(canvas_id: canvas)
  end

  it "skips a source with no retained evidence" do
    allow(client).to receive(:canvas_ids)

    highlights = resolver.call([ { title: "Elsewhere", url: "http://example.test/other", pages: [ "3" ] } ], answer)

    expect(highlights).to eq({})
    expect(client).not_to have_received(:canvas_ids)
  end
end
