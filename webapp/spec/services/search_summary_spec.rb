# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchSummary do
  it "includes bounded result metadata and excludes unrelated fields" do
    document = SolrDocument.new(title_display_tesi: "Frogs", vector: [ 0.5 ], all_search_tesi: "private")
    context = described_class.verifier.verify(described_class.token(query: "frogs", documents: [ document ] * 30))
    expect(context["results"].length).to eq(20)
    expect(context["results"].first.fetch("title_display_tesi")).to eq([ "Frogs" ])
    expect(context["results"].first).not_to have_key("vector")
    expect(context["results"].first).not_to have_key("all_search_tesi")
  end

  it "uses the existing completion client without tools" do
    completion = Chat::LiteLlmCompletionRequest::Completion.new(
      message: { "content" => "These results concern frogs." }, tool_calls: [], finish_reason: "stop"
    )
    request = instance_double(Chat::LiteLlmCompletionRequest, stream_completion: completion)
    allow(Chat::LiteLlmCompletionRequest).to receive(:new).and_return(request)

    expect(described_class.new({ query: "frogs", results: [] }).call).to eq("These results concern frogs.")
    expect(Chat::LiteLlmCompletionRequest).to have_received(:new).with(messages: [
      hash_including("role" => "system"),
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
