# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchSummary do
  let(:cocina_json) do
    {
      externalIdentifier: "druid:bb112zx3193",
      description: { title: [ { value: "African clawed frog" } ], note: [] }
    }.to_json
  end

  it "includes every supplied result and excludes unrelated fields" do
    document = SolrDocument.new(title_display_tesi: "Frogs", vector: [ 0.5 ], all_search_tesi: "private", cocina_ss: cocina_json)
    context = described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ] * 30))
    expect(context["results"].length).to eq(30)
    expect(context["results"].first.fetch("title")).to eq([ "Frogs" ])
    expect(context["results"].first.keys).to match_array(described_class::FIELDS.map(&:to_s))
  end

  it "bounds the number of values and their length within each field" do
    cocina_json = {
      externalIdentifier: "druid:bb112zx3193",
      description: {
        title: [ { value: "Frogs" } ],
        note: Array.new(12) { |index| { type: "abstract", value: "#{index} #{'a' * 2_000}" } }
      }
    }.to_json
    document = SolrDocument.new(title_display_tesi: "Frogs", "cocina_ss" => cocina_json)
    context = described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ]))

    abstracts = context["results"].first.fetch("abstracts")
    expect(abstracts.length).to eq(10)
    expect(abstracts.map(&:length)).to all(eq(1_000))
  end

  it "includes the abstracts from the results" do
    cocina_json = {
      externalIdentifier: "druid:bb112zx3193",
      description: {
        title: [ { value: "Frogs" } ],
        note: [ { type: "abstract", value: "A survey of California frogs." } ]
      }
    }.to_json
    document = SolrDocument.new(title_display_tesi: "Frogs", "cocina_ss" => cocina_json)
    context = described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ]))
    expect(context["results"].first.fetch("abstracts")).to eq([ "A survey of California frogs." ])
  end

  it "uses the existing completion client without tools" do
    completion = Chat::LiteLlmCompletionRequest::Completion.new(
      message: { "content" => "These results concern frogs." }, tool_calls: [], finish_reason: "stop"
    )
    request = instance_double(Chat::LiteLlmCompletionRequest, stream_completion: completion)
    allow(Chat::LiteLlmCompletionRequest).to receive(:new).and_return(request)

    expect(described_class.new({ query: "frogs", results: [] }).call).to eq("These results concern frogs.")
    expect(Chat::LiteLlmCompletionRequest).to have_received(:new).with(
      messages: [
        hash_including("role" => "system", "content" => /Format the response as Markdown/),
        { "role" => "user", "content" => { query: "frogs", results: [] }.to_json }
      ],
      reasoning_effort: "low",
      max_tokens: 800
    )
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
