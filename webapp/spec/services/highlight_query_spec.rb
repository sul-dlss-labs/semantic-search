# frozen_string_literal: true

require "rails_helper"

RSpec.describe HighlightQuery do
  def highlight(query)
    described_class.new(query).call
  end

  it "keeps only the quoted phrase of a question about it" do
    expect(highlight('Is there anything about "Phil Knight" in the repository?')).to eq('"Phil Knight"')
  end

  it "keeps the words alongside a quoted phrase that are not filler" do
    expect(highlight('"Phil Knight" Nike founding')).to eq('"Phil Knight" Nike founding')
  end

  it "turns curly quotes into the straight quotes Solr reads as a phrase" do
    expect(highlight("anything about “Phil Knight”")).to eq('"Phil Knight"')
  end

  it "drops the filler from an unquoted question" do
    expect(highlight("What do the documents say about water rights?")).to eq("water rights")
  end

  it "ignores the case and apostrophe style of filler words" do
    expect(highlight("What’s There about Frogs")).to eq("Frogs")
  end

  it "strips trailing punctuation, which Solr would read as a wildcard" do
    expect(highlight("who was Phil Knight?")).to eq("Phil Knight")
  end

  it "leaves boolean operators alone" do
    expect(highlight("frogs AND toads")).to eq("frogs AND toads")
  end

  it "leaves a plain keyword search unchanged" do
    expect(highlight("water rights")).to eq("water rights")
  end

  it "falls back to the whole query when it is nothing but filler" do
    expect(highlight("what is there?")).to eq("what is there?")
  end
end
