# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchSummary do
  # Builds a document whose Cocina carries the supplied description notes.
  def document_with_notes(notes)
    SolrDocument.new(
      id: "bb112zx3193",
      "cocina_ss" => {
        externalIdentifier: "druid:bb112zx3193",
        description: { title: [ { value: "Frogs" } ], note: notes }
      }.to_json
    )
  end

  def abstract_for(document)
    described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ]))
                   .fetch("results").first.fetch("abstract")
  end

  it "includes bounded result metadata and excludes unrelated fields" do
    document = SolrDocument.new(title_display_tesi: "Frogs", vector: [ 0.5 ], all_search_tesi: "private")
    context = described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ] * 30))
    expect(context["results"].length).to eq(20)
    expect(context["results"].first.fetch("title_display_tesi")).to eq([ "Frogs" ])
    expect(context["results"].first).not_to have_key("vector")
    expect(context["results"].first).not_to have_key("all_search_tesi")
  end

  it "sends an empty abstract for a document with no Cocina" do
    expect(abstract_for(SolrDocument.new(title_display_tesi: "Frogs"))).to eq("")
  end

  it "collapses whitespace in the abstract" do
    document = document_with_notes([ { type: "abstract", value: "Frogs\n\n   and toads." } ])
    expect(abstract_for(document)).to eq("Frogs and toads.")
  end

  it "includes archival scope and content notes" do
    document = document_with_notes([ { type: "scope and content", value: "Field notes on frogs." } ])
    expect(abstract_for(document)).to eq("Field notes on frogs.")
  end

  it "joins multiple abstract notes" do
    document = document_with_notes([
      { type: "abstract", value: "Frogs." }, { type: "scope and content", value: "And toads." }
    ])
    expect(abstract_for(document)).to eq("Frogs. And toads.")
  end

  it "bounds a long abstract" do
    document = document_with_notes([ { type: "abstract", value: "frog " * 500 } ])
    abstract = abstract_for(document)
    expect(abstract.length).to be <= described_class::MAX_ABSTRACT_CHARACTERS
    expect(abstract).to end_with("...")
  end

  it "uses the existing completion client without tools" do
    completion = Chat::LiteLlmCompletionRequest::Completion.new(
      message: { "content" => "These results concern frogs." }, tool_calls: [], finish_reason: "stop"
    )
    request = instance_double(Chat::LiteLlmCompletionRequest, stream_completion: completion)
    allow(Chat::LiteLlmCompletionRequest).to receive(:new).and_return(request)

    expect(described_class.new({ query: "frogs", results: [] }).call).to eq("These results concern frogs.")
    expect(Chat::LiteLlmCompletionRequest).to have_received(:new).with(messages: [
      hash_including("role" => "system", "content" => /Format the response as Markdown/),
      { "role" => "user", "content" => { query: "frogs", results: [] }.to_json }
    ])
  end

  it "rejects an incomplete answer" do
    completion = Chat::LiteLlmCompletionRequest::Completion.new(
      message: { "content" => "These results" }, tool_calls: [], finish_reason: "length"
    )
    allow(Chat::LiteLlmCompletionRequest).to receive(:new).and_return(
      instance_double(Chat::LiteLlmCompletionRequest, stream_completion: completion)
    )
    expect { described_class.new({}).call }.to raise_error(Chat::LiteLlmCompletionRequest::RequestError)
  end
end
