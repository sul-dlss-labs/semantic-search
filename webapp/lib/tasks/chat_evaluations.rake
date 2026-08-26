# frozen_string_literal: true

require Rails.root.join("lib/chat_evaluation/load")

namespace :chat do
  desc "Evaluate the deployed chat endpoint with an independent LiteLLM model"
  task evaluate: :environment do
    runner = Chat::Evaluation::Runner.new(
      target_url: ENV.fetch("CHAT_EVAL_TARGET_URL", "https://semantic-search-demo.stanford.edu"),
      cases_path: ENV.fetch("CHAT_EVAL_CASES", Rails.root.join("lib/chat_evaluation/chat_evaluations.yml")),
      case_id: ENV["CHAT_EVAL_CASE"],
      minimum_score: ENV.fetch("CHAT_EVAL_MIN_SCORE", 0.8),
      runs: ENV.fetch("CHAT_EVAL_RUNS", 1),
      required_pass_rate: ENV.fetch("CHAT_EVAL_PASS_RATE", 1.0),
      report_path: ENV["CHAT_EVAL_REPORT"]
    )
    result = runner.run
    abort "One or more chat evaluations failed" unless result.passed
  end
end
