# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::HighlightSelector do
  subject(:selector) { described_class.new }

  # One line per OCR line, the way sdr-harvest's ALTO extractor writes chunk text.
  let(:chunk) do
    <<~TEXT
      Cantor Arts Center. Collections and
      special exhibitions are on view Wednes-
      day-Sunday and Thursday. Admission is free of charge.
    TEXT
  end

  def words_only(text)
    text.gsub(/[^[:alnum:]]+/, " ").squeeze(" ").strip
  end

  it "never returns a phrase that crosses a line break" do
    phrases = selector.call(chunk_texts: [ chunk ])

    expect(phrases).to be_present
    phrases.each do |phrase|
      containing_line = chunk.split("\n").find { |line| words_only(line).include?(words_only(phrase)) }
      expect(containing_line).to be_present, "#{phrase.inspect} does not sit within a single line"
    end
  end

  it "excludes the last token of a line, which may be a de-hyphenation join" do
    phrases = selector.call(chunk_texts: [ chunk ]).join(" | ")

    expect(phrases).not_to include("Wednes")
    expect(phrases).not_to include("charge")
  end

  it "biases toward the words the answer actually used" do
    focused = selector.call(chunk_texts: [ chunk ], focus_text: "Admission to the exhibitions is free.")

    expect(focused.first).to eq("Thursday Admission is free")
  end

  it "never anchors a phrase on a stopword" do
    phrases = selector.call(chunk_texts: [ "the quick brown fox jumped over the lazy dog and away\n" ])

    expect(phrases).to be_present
    phrases.each do |phrase|
      words = phrase.downcase.split
      expect(described_class::STOPWORDS).not_to include(words.first)
      expect(described_class::STOPWORDS).not_to include(words.last)
    end
  end

  it "strips Markdown syntax left by the PDF extractor" do
    phrases = selector.call(chunk_texts: [ "## Consolidated Statements of Financial Position 2004\n" ])

    expect(phrases.first).not_to include("#")
    expect(phrases.first).to include("Consolidated Statements")
  end

  it "returns nothing rather than junk when a line is too short to use" do
    expect(selector.call(chunk_texts: [ "ARTS\nexhibits\n" ])).to eq([])
  end

  it "returns nothing when there is no chunk text at all" do
    expect(selector.call(chunk_texts: [])).to eq([])
  end
end
