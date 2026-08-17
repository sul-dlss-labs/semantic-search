# frozen_string_literal: true

require "net/http"
require "json"

class GeminiEmbedding
  # See https://docs.litellm.ai/blog/gemini_embedding_2_ga
  DEFAULT_QUERY_INSTRUCTION = "search result"

  INSTRUMENTATION_EVENT = "request.litellm"
  MODEL = "gemini-embedding-2"
  DIMENSIONS = 768

  # Creates embeddings using Gemini Embedding 2 through a LiteLLM proxy.
  #
  # @param input [Array<String>] texts to embed
  # @param instruction [String, nil] when provided, each text is prefixed with
  #   the instruction to guide the embedding. Pass
  #   DEFAULT_QUERY_INSTRUCTION (or any task-specific string) for query inputs;
  #   leave nil when embedding documents/passages.
  # @return [Array<Array<Float>>] one embedding vector per input string
  # @raise [RuntimeError] if the API request fails
  def embedding(input:, instruction: nil)
    return [] if input.empty?

    api_base = ENV["LITELLM_API_BASE"]
    api_key = ENV["LITELLM_API_KEY"]
    raise "LITELLM_API_BASE environment variable is not set" if api_base.blank?
    raise "LITELLM_API_KEY environment variable is not set" if api_key.blank?

    api_base = api_base.chomp("/")
    api_base = "#{api_base}/v1" unless api_base.end_with?("/v1")
    uri = URI("#{api_base}/embeddings")
    model = ENV.fetch("LITELLM_EMBEDDING_MODEL", MODEL)
    request_input = input.map { |text| instruction ? "task: #{instruction} | query: #{text}" : text }
    request = Net::HTTP::Post.new(
      uri,
      "Authorization" => "Bearer #{api_key}",
      "Content-Type" => "application/json"
    )
    request.body = {
      model: model,
      input: request_input,
      dimensions: DIMENSIONS
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    instrument_request(model, request_input, instruction.present?) do |payload|
      response = http.request(request)
      payload[:http_status] = response.code.to_i
      payload[:request_id] = response["x-litellm-call-id"] || response["x-request-id"]

      unless response.is_a?(Net::HTTPSuccess)
        raise "LiteLLM embedding request failed (#{response.code}): #{response.body}"
      end

      parsed_response = JSON.parse(response.body)
      add_response_metadata(payload, parsed_response)
      parsed_response.fetch("data").sort_by { |item| item.fetch("index") }.map { |item| item.fetch("embedding") }
    end
  end

  private

  def instrument_request(model, request_input, instruction_present, &)
    ActiveSupport::Notifications.instrument(
      INSTRUMENTATION_EVENT,
      model: model,
      operation: "embeddings",
      input_count: request_input.length,
      input_characters: request_input.sum(&:length),
      instruction_present: instruction_present,
      dimensions: DIMENSIONS,
      &
    )
  end

  def add_response_metadata(payload, response)
    payload[:response_id] = response["id"] if response["id"]
    usage = response["usage"]
    return unless usage

    payload[:prompt_tokens] = usage["prompt_tokens"] if usage["prompt_tokens"]
    payload[:total_tokens] = usage["total_tokens"] if usage["total_tokens"]
  end
end
