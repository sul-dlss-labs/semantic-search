# frozen_string_literal: true

require "json"
require "net/http"

module Chat
  # Streams OpenAI-compatible chat completions from the configured LiteLLM proxy.
  class LiteLlmClient
    INSTRUMENTATION_EVENT = "request.litellm"
    MAX_ERROR_DETAIL_CHARACTERS = 2_000

    class RequestError < StandardError; end

    Completion = Data.define(:message, :tool_calls, :finish_reason) do
      def complete?
        finish_reason.blank? || %w[stop tool_calls function_call].include?(finish_reason.downcase)
      end

      def length_limited?
        %w[length max_tokens].include?(finish_reason.to_s.downcase)
      end
    end

    def stream_completion(messages:, tools: nil, tool_choice: nil)
      uri, model, request = build_request(messages, tools, tool_choice)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 120

      instrument_request(model, messages) do |payload|
        perform_request(http, request, payload) do |data|
          yield data if block_given?
        end
      end
    end

    private

    def build_request(messages, tools, tool_choice)
      api_base = ENV["LITELLM_API_BASE"]
      api_key = ENV["LITELLM_API_KEY"]
      model = ENV["LITELLM_CHAT_MODEL"]
      raise "LITELLM_API_BASE environment variable is not set" if api_base.blank?
      raise "LITELLM_API_KEY environment variable is not set" if api_key.blank?
      raise "LITELLM_CHAT_MODEL environment variable is not set" if model.blank?

      api_base = api_base.chomp("/")
      api_base = "#{api_base}/v1" unless api_base.end_with?("/v1")
      uri = URI("#{api_base}/chat/completions")
      request = Net::HTTP::Post.new(
        uri,
        "Authorization" => "Bearer #{api_key}",
        "Content-Type" => "application/json",
        "Accept" => "text/event-stream"
      )
      request.body = {
        model: model,
        messages: messages,
        tools: tools.presence,
        tool_choice: tool_choice || (tools.present? ? "auto" : nil),
        max_tokens: Rails.configuration.x.chat.max_output_tokens,
        stream: true,
        stream_options: { include_usage: true }
      }.compact.to_json

      [ uri, model, request ]
    end

    def perform_request(http, request, payload)
      content = +""
      tool_calls = {}
      parser = EventStreamParser.new

      http.request(request) do |response|
        payload[:http_status] = response.code.to_i
        payload[:request_id] = response["x-litellm-call-id"] || response["x-request-id"]
        raise_request_error(response) unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          parser.feed(chunk) do |event_data|
            process_event(event_data, content, tool_calls, payload) { |delta| yield delta }
          end
        end
        parser.finish do |event_data|
          process_event(event_data, content, tool_calls, payload) { |delta| yield delta }
        end
      end
      raise RequestError, "LiteLLM stream ended before its done event" unless payload[:stream_complete]

      calls = tool_calls.sort_by { |index, _call| index }.map do |index, call|
        call["id"] ||= "call_#{index}"
        call
      end
      message = { "role" => "assistant", "content" => content.presence }
      message["tool_calls"] = calls if calls.any?
      Completion.new(message:, tool_calls: calls, finish_reason: payload[:finish_reason])
    end

    def raise_request_error(response)
      body = response.body.to_s
      detail = JSON.parse(body).dig("error", "message")
      detail = body if detail.blank?
      detail = detail.to_s.truncate(MAX_ERROR_DETAIL_CHARACTERS)
      suffix = detail.present? ? ": #{detail}" : ""
      raise RequestError, "LiteLLM chat request failed (#{response.code})#{suffix}"
    rescue JSON::ParserError
      detail = body.truncate(MAX_ERROR_DETAIL_CHARACTERS)
      raise RequestError, "LiteLLM chat request failed (#{response.code}): #{detail}"
    end

    def process_event(event_data, content, tool_calls, payload)
      if event_data == "[DONE]"
        payload[:stream_complete] = true
        return
      end

      event = JSON.parse(event_data)
      payload[:response_id] ||= event["id"]
      add_usage(payload, event["usage"])
      payload[:finish_reason] = event.dig("choices", 0, "finish_reason") || payload[:finish_reason]
      delta = event.dig("choices", 0, "delta") || {}

      if delta["content"].present?
        content << delta["content"]
        yield delta["content"]
      end

      Array(delta["tool_calls"]).each do |fragment|
        call = (tool_calls[fragment.fetch("index")] ||= {
          "id" => nil,
          "type" => "function",
          "function" => { "name" => +"", "arguments" => +"" }
        })
        call["id"] ||= fragment["id"]
        function = fragment["function"] || {}
        call["function"]["name"] << function["name"] if function["name"]
        call["function"]["arguments"] << function["arguments"] if function["arguments"]
      end
    rescue JSON::ParserError => e
      raise "LiteLLM returned an invalid streaming event: #{e.message}"
    end

    def add_usage(payload, usage)
      return unless usage

      payload[:prompt_tokens] = usage["prompt_tokens"] if usage["prompt_tokens"]
      payload[:completion_tokens] = usage["completion_tokens"] if usage["completion_tokens"]
      payload[:total_tokens] = usage["total_tokens"] if usage["total_tokens"]
    end

    def instrument_request(model, messages, &)
      ActiveSupport::Notifications.instrument(
        INSTRUMENTATION_EVENT,
        model: model,
        operation: "chat.completions",
        input_count: messages.length,
        input_characters: messages.sum { |message| message["content"].to_s.length },
        instruction_present: messages.any? { |message| message["role"] == "system" },
        &
      )
    end

    # Incrementally parses data fields from a server-sent event stream.
    class EventStreamParser
      def initialize
        @buffer = +""
        @data_lines = []
      end

      def feed(chunk, &)
        @buffer << chunk
        consume_lines(&)
      end

      def finish
        consume_line(@buffer.delete_suffix("\r")) { |data| yield data } if @buffer.present?
        @buffer.clear
        dispatch { |data| yield data }
      end

      private

      def consume_lines
        while (newline = @buffer.index("\n"))
          line = @buffer.slice!(0..newline).delete_suffix("\n").delete_suffix("\r")
          consume_line(line) { |data| yield data }
        end
      end

      def consume_line(line)
        if line.empty?
          dispatch { |data| yield data }
        elsif line.start_with?("data:")
          @data_lines << line.delete_prefix("data:").sub(/\A /, "")
        end
      end

      def dispatch
        return if @data_lines.empty?

        data = @data_lines.join("\n")
        @data_lines.clear
        yield data
      end
    end
  end
end
