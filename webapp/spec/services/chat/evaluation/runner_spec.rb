# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require Rails.root.join("lib/chat_evaluation/load")

RSpec.describe Chat::Evaluation::Runner do
  let(:chat_client) { instance_double(Chat::Evaluation::RemoteChatClient) }
  let(:judge) { instance_double(Chat::Evaluation::LiteLlmJudge, model: "judge-model") }
  let(:output) { StringIO.new }
  let(:chat_result) do
    Chat::Evaluation::RemoteChatClient::Result.new(
      answer: "John Lynch threw the first pitch in Marlins history in Erie, Pennsylvania.",
      sources: [ { "title" => "Marlins history", "url" => "https://example.test/marlins" } ]
    )
  end
  let(:verdict) do
    Chat::Evaluation::LiteLlmJudge::Verdict.new(
      pass: true,
      score: 0.9,
      reason: "All essential facts are present.",
      criteria: []
    )
  end

  around do |example|
    Dir.mktmpdir("chat-evaluation-spec") do |directory|
      @directory = Pathname(directory)
      @cases_path = @directory.join("cases.yml")
      @report_path = @directory.join("report.json")
      @cases_path.write(<<~YAML)
        cases:
          - id: marlins_first_pitch
            question: Who threw out the first pitch for the Marlins?
            history:
              - role: user
                content: Who threw it?
              - role: assistant
                content: I could not find it.
            reference_answer: John Lynch threw the first pitch in Marlins history in Erie, Pennsylvania.
            rubric:
              - Identifies John Lynch.
            require_citations: true
      YAML
      example.run
    end
  end

  before do
    allow(chat_client).to receive(:ask).and_return(chat_result)
    allow(judge).to receive(:evaluate).and_return(verdict)
  end

  it "passes a semantically correct, cited response and writes its evidence to JSON" do
    result = build_runner.run

    expect(result.passed).to be(true)
    expect(chat_client).to have_received(:ask).with(
      "Who threw out the first pitch for the Marlins?",
      history: [
        { role: "user", content: "Who threw it?" },
        { role: "assistant", content: "I could not find it." }
      ]
    )
    report = JSON.parse(@report_path.read)
    expect(report).to include("passed" => true, "evaluation_model" => "judge-model")
    expect(report.dig("cases", 0, "attempts", 0)).to include(
      "answer" => chat_result.answer,
      "citations_passed" => true,
      "passed" => true
    )
    expect(report.dig("cases", 0, "history")).to eq(
      [
        { "role" => "user", "content" => "Who threw it?" },
        { "role" => "assistant", "content" => "I could not find it." }
      ]
    )
    expect(output.string).to include("attempt 1: PASS", "Chat evaluation PASSED")
  end

  it "fails a response that has no verified clickable citation" do
    allow(chat_client).to receive(:ask).and_return(
      Chat::Evaluation::RemoteChatClient::Result.new(answer: chat_result.answer, sources: [])
    )

    result = build_runner.run

    expect(result.passed).to be(false)
    expect(result.report.dig(:cases, 0, :attempts, 0)).to include(citations_passed: false, passed: false)
    expect(output.string).to include("citations missing", "Chat evaluation FAILED")
  end

  def build_runner
    described_class.new(
      target_url: "https://chat.example",
      cases_path: @cases_path,
      report_path: @report_path,
      chat_client:,
      judge:,
      output:
    )
  end
end
