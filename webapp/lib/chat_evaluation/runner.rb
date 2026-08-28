# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"

module Chat
  module Evaluation
    # Runs configured questions against a deployment and writes an auditable JSON report.
    class Runner
      RunResult = Data.define(:passed, :report_path, :report)

      def initialize(
        target_url:,
        cases_path: Rails.root.join("lib/chat_evaluation/chat_evaluations.yml"),
        case_id: nil,
        minimum_score: 0.8,
        runs: 1,
        required_pass_rate: 1.0,
        report_path: nil,
        chat_client: nil,
        judge: nil,
        output: $stdout
      )
        @target_url = target_url
        @cases_path = Pathname(cases_path)
        @case_id = case_id.presence
        @minimum_score = Float(minimum_score)
        @runs = Integer(runs)
        @required_pass_rate = Float(required_pass_rate)
        @report_path = report_path && Pathname(report_path)
        @chat_client = chat_client || RemoteChatClient.new(base_url: target_url)
        @judge = judge || LiteLlmJudge.new
        @output = output
        validate_options!
      end

      def run
        started_at = Time.current
        cases = load_cases
        results = cases.map { |evaluation_case| evaluate_case(evaluation_case) }
        passed = results.all? { |result| result.fetch(:passed) }
        report = {
          target_url: @target_url,
          evaluation_model: @judge.model,
          started_at: started_at.iso8601,
          finished_at: Time.current.iso8601,
          minimum_score: @minimum_score,
          runs_per_case: @runs,
          required_pass_rate: @required_pass_rate,
          passed:,
          cases: results
        }
        report_path = write_report(report)
        @output.puts("Chat evaluation #{passed ? 'PASSED' : 'FAILED'}; report: #{report_path}")
        RunResult.new(passed:, report_path:, report:)
      end

      private

      def validate_options!
        raise ArgumentError, "CHAT_EVAL_RUNS must be at least 1" unless @runs.positive?
        raise ArgumentError, "CHAT_EVAL_MIN_SCORE must be between 0 and 1" unless @minimum_score.between?(0, 1)
        return if @required_pass_rate.positive? && @required_pass_rate <= 1

        raise ArgumentError, "CHAT_EVAL_PASS_RATE must be greater than 0 and at most 1"
      end

      def load_cases
        document = YAML.safe_load_file(@cases_path, symbolize_names: true)
        cases = Array(document[:cases])
        cases.select! { |evaluation_case| evaluation_case[:id].to_s == @case_id } if @case_id
        raise ArgumentError, "No chat evaluation cases matched #{@case_id.inspect}" if cases.empty?

        cases.each { |evaluation_case| validate_case!(evaluation_case) }
      end

      def validate_case!(evaluation_case)
        %i[id question reference_answer rubric].each do |key|
          raise ArgumentError, "Chat evaluation case is missing #{key}" if evaluation_case[key].blank?
        end
        Array(evaluation_case[:history]).each do |message|
          role = message[:role].to_s
          content = message[:content]
          next if %w[user assistant].include?(role) && content.is_a?(String) && content.present?

          raise ArgumentError, "Chat evaluation case #{evaluation_case[:id]} has an invalid history message"
        end
      end

      def evaluate_case(evaluation_case)
        @output.puts("Evaluating #{evaluation_case.fetch(:id)}...")
        attempts = Array.new(@runs) { |index| evaluate_attempt(evaluation_case, index + 1) }
        pass_rate = attempts.count { |attempt| attempt.fetch(:passed) }.fdiv(@runs)
        {
          id: evaluation_case.fetch(:id),
          question: evaluation_case.fetch(:question),
          reference_answer: evaluation_case.fetch(:reference_answer),
          rubric: evaluation_case.fetch(:rubric),
          history: evaluation_case.fetch(:history, []),
          require_citations: evaluation_case.fetch(:require_citations, false),
          pass_rate:,
          passed: pass_rate >= @required_pass_rate,
          attempts:
        }
      end

      def evaluate_attempt(evaluation_case, attempt_number)
        chat_result = @chat_client.ask(
          evaluation_case.fetch(:question),
          history: evaluation_case.fetch(:history, [])
        )
        verdict = @judge.evaluate(
          question: evaluation_case.fetch(:question),
          reference_answer: evaluation_case.fetch(:reference_answer),
          rubric: evaluation_case.fetch(:rubric),
          answer: chat_result.answer,
          sources: chat_result.sources
        )
        citations_passed = !evaluation_case.fetch(:require_citations, false) ||
          valid_citations?(chat_result.answer, chat_result.sources)
        passed = verdict.pass && verdict.score >= @minimum_score && citations_passed
        @output.puts(
          "  attempt #{attempt_number}: #{passed ? 'PASS' : 'FAIL'} " \
          "(score #{format('%.2f', verdict.score)}, citations #{citations_passed ? 'present' : 'missing'})"
        )
        {
          attempt: attempt_number,
          answer: chat_result.answer,
          sources: chat_result.sources,
          citations_passed:,
          judge: {
            pass: verdict.pass,
            score: verdict.score,
            reason: verdict.reason,
            criteria: verdict.criteria
          },
          passed:
        }
      rescue StandardError => e
        @output.puts("  attempt #{attempt_number}: ERROR (#{e.class}: #{e.message})")
        {
          attempt: attempt_number,
          passed: false,
          error: { class: e.class.name, message: e.message }
        }
      end

      def valid_citations?(answer, sources)
        verified_urls = sources.filter_map do |source|
          uri = URI(source["url"].to_s)
          uri.to_s if source["title"].present? && %w[http https].include?(uri.scheme) && uri.host.present?
        rescue URI::InvalidURIError
          nil
        end
        cited_urls = answer.scan(/\[[^\]\n]+\]\((?:<([^>\n]+)>|([^)\s]+))\)/).map { |match| match.compact.first }

        (verified_urls & cited_urls).any?
      end

      def write_report(report)
        path = @report_path || Rails.root.join("tmp/chat_evaluations/#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
        FileUtils.mkdir_p(path.dirname)
        path.write(JSON.pretty_generate(report) << "\n")
        path
      end
    end
  end
end
