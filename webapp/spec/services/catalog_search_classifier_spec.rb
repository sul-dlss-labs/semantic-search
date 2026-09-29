require "rails_helper"

RSpec.describe CatalogSearchClassifier do
  describe "#call" do
    def classify(query)
      described_class.new(query).call
    end

    it "uses vector search for conceptual questions" do
      expect(classify("What football player has a community youth leadership foundation?")).to eq("vector")
      expect(classify("How did athletes support young people in their communities?")).to eq("vector")
    end

    it "uses keyword search for explicit titles, phrases, and identifiers" do
      expect(classify("Interview with John Lynch")).to eq("keyword")
      expect(classify('"Interview with John Lynch"')).to eq("keyword")
      expect(classify("zv638jb7154")).to eq("keyword")
    end

    it "uses hybrid search when a question includes an exact entity" do
      expect(classify("What does John Lynch say about his foundation?")).to eq("hybrid")
      expect(classify('What does "John Lynch" say about leadership?')).to eq("hybrid")
    end

    it "uses hybrid search when the intent is unclear" do
      expect(classify("football youth foundation")).to eq("hybrid")
      expect(classify("John Lynch youth foundation")).to eq("hybrid")
    end
  end
end
