# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/chat_evaluation/lite_llm_judge")

RSpec.describe Chat::Evaluation::LiteLlmJudge do
  subject(:judge) do
    described_class.new(api_base: "https://litellm.example/v1/", api_key: "secret", model: "judge-model")
  end

  let(:http) { instance_double(Net::HTTP) }
  let(:response) { Net::HTTPOK.new("1.1", "200", "OK") }

  before do
    allow(Net::HTTP).to receive(:new).with("litellm.example", 443).and_return(http)
    allow(http).to receive(:use_ssl=).with(true)
    allow(http).to receive(:open_timeout=).with(10)
    allow(http).to receive(:read_timeout=).with(120)
  end

  it "returns a structured semantic verdict from an OpenAI-compatible completion" do
    content = {
      pass: true,
      score: 0.95,
      reason: "The candidate contains all required facts.",
      criteria: [ { criterion: "Names John Lynch", pass: true, reason: "Explicitly named." } ]
    }.to_json
    allow(response).to receive(:body).and_return(
      { choices: [ { message: { content: "```json\n#{content}\n```" } } ] }.to_json
    )
    allow(http).to receive(:request) do |request|
      payload = JSON.parse(request.body)
      expect(request.uri.to_s).to eq("https://litellm.example/v1/chat/completions")
      expect(request["Authorization"]).to eq("Bearer secret")
      expect(payload).to include("model" => "judge-model", "stream" => false)
      expect(payload).not_to have_key("temperature")
      expect(payload.dig("messages", 1, "content")).to include(
        "John Lynch threw the first pitch",
        "The answer says John Lynch"
      )
      response
    end

    verdict = judge.evaluate(
      question: "Who threw it?",
      reference_answer: "John Lynch threw the first pitch.",
      rubric: [ "The answer says John Lynch" ],
      answer: "It was John Lynch.",
      sources: [ { "title" => "Source", "url" => "https://example.test" } ]
    )

    expect(verdict.pass).to be(true)
    expect(verdict.score).to eq(0.95)
    expect(verdict.reason).to include("all required facts")
  end

  it "rejects a malformed verdict" do
    allow(response).to receive(:body).and_return(
      { choices: [ { message: { content: '{"pass":"yes","score":2,"reason":"No"}' } } ] }.to_json
    )
    allow(http).to receive(:request).and_return(response)

    expect do
      judge.evaluate(question: "Q", reference_answer: "R", rubric: [ "C" ], answer: "A", sources: [])
    end.to raise_error(described_class::RequestError, "Evaluation verdict pass must be true or false")
  end
end
