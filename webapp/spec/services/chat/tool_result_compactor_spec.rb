# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::ToolResultCompactor do
  subject(:compactor) { described_class.new }

  it "preserves ranked passage evidence while bounding long excerpts" do
    text = compactor.call(
      text: "unbounded",
      structured_content: {
        passages: [
          {
            rank: 1,
            text: "x" * 3_000,
            chunk_id: "chunk-1",
            chunk_index: 4,
            page: "571",
            document_id: "vm857hw3603",
            document_title: "Stanford report. Volume 36, 2003-2004",
            url: "/catalog/vm857hw3603"
          }
        ]
      }
    )

    expect(text).to start_with("Passage evidence:\n1. Stanford report. Volume 36, 2003-2004")
    expect(text).to include("page 571", "chunk 4", "Source: /catalog/vm857hw3603")
    expect(text.length).to be < 2_300
  end

  it "deduplicates evidence across repeated tool results" do
    result = {
      text: "Frog passage",
      structured_content: {
        passages: [
          { rank: 1, text: "Frog passage", chunk_id: "chunk-1", document_id: "frogs" }
        ]
      }
    }

    expect(compactor.call(result)).to include("Frog passage")
    expect(compactor.call(result)).to eq("No new evidence; these results duplicate evidence already returned.")
  end

  it "retains document pagination instructions when compacting chunks" do
    text = compactor.call(
      text: "Document chunks",
      structured_content: {
        document_id: "frogs",
        returned_chunks: 1,
        total_chunks: 20,
        complete: false,
        next_cursor: "next-page",
        chunks: [ { id: "chunk-1", text: "Evidence", chunk_index: 0 } ]
      }
    )

    expect(text).to include("Document frogs: 1 of 20 chunks", "Evidence", "Continue with cursor: next-page")
  end
end
