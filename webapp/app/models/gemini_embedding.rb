# frozen_string_literal: true

require "net/http"
require "json"

class GeminiEmbedding
  DEFAULT_QUERY_INSTRUCTION = "Given a web search query, retrieve relevant passages that answer the query"

  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent"

  # Creates embeddings using Google's gemini-embedding-2 model via the REST API.
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

    api_key = ENV["GEMINI_API_KEY"]
    raise "GEMINI_API_KEY environment variable is not set" if api_key.blank?

    results = []

    input.each do |text|
      content = text
      if instruction
        content = "Instruct: #{instruction}\nQuery: #{text}"
      end

      uri = URI("#{BASE_URL}?key=#{api_key}")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      request.body = {
        content: {
          parts: [{ text: content }]
        }
      }.to_json

      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true

      response = https.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "GeminiEmbedding API request failed (#{response.code}): #{response.body}"
      end

      data = JSON.parse(response.body)
      results << data.dig("embedding", "values")
    end

    results
  end
end
