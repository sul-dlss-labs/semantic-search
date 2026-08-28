# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"

module Chat
  module Evaluation
    # Exercises the deployed chat endpoint through the same HTTP interface as a browser.
    class RemoteChatClient
      Result = Data.define(:answer, :sources)

      class RequestError < StandardError; end

      def initialize(base_url:)
        @base_uri = URI(base_url)
        raise ArgumentError, "CHAT_EVAL_TARGET_URL must use http or https" unless %w[http https].include?(@base_uri.scheme)

        @base_uri.path = "/" if @base_uri.path.blank?
      end

      def ask(question, history: [])
        csrf_token, cookies = fetch_session
        accumulator = StreamAccumulator.new
        uri = endpoint_uri
        request = Net::HTTP::Post.new(
          uri,
          "Accept" => "text/event-stream",
          "Content-Type" => "application/json",
          "Cookie" => cookies,
          "X-CSRF-Token" => csrf_token
        )
        messages = Array(history).map { |message| message.to_h.stringify_keys }
        messages << { "role" => "user", "content" => question }
        request.body = { messages: }.to_json

        perform(uri, request) do |response|
          raise_request_error(response) unless response.is_a?(Net::HTTPSuccess)

          response.read_body { |chunk| accumulator.feed(chunk) }
        end
        accumulator.finish
      end

      private

      def fetch_session
        uri = endpoint_uri
        request = Net::HTTP::Get.new(uri, "Accept" => "text/html")
        response = perform(uri, request)
        raise_request_error(response) unless response.is_a?(Net::HTTPSuccess)

        token = response.body.to_s[/<meta\s+[^>]*name=["']csrf-token["'][^>]*content=["']([^"']+)["'][^>]*>/i, 1]
        raise RequestError, "The chat page did not contain a CSRF token" if token.blank?

        cookies = Array(response.get_fields("set-cookie")).filter_map { |cookie| cookie.split(";", 2).first }.join("; ")
        [ CGI.unescapeHTML(token), cookies ]
      end

      def endpoint_uri
        URI.join(@base_uri.to_s.end_with?("/") ? @base_uri.to_s : "#{@base_uri}/", "chat")
      end

      def perform(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 180
        return http.request(request) unless block_given?

        http.request(request) { |response| yield response }
      end

      def raise_request_error(response)
        detail = response.body.to_s.truncate(2_000)
        suffix = detail.present? ? ": #{detail}" : ""
        raise RequestError, "Chat endpoint returned HTTP #{response.code}#{suffix}"
      end

      # Incrementally collects the browser-facing event stream into one final response.
      class StreamAccumulator
        def initialize
          @buffer = +""
          @event = nil
          @data_lines = []
          @answer = +""
          @sources = []
          @done = false
        end

        def feed(chunk)
          @buffer << chunk
          consume_lines
        end

        def finish
          consume_line(@buffer.delete_suffix("\r")) if @buffer.present?
          @buffer.clear
          dispatch
          raise RequestError, "Chat stream ended without a done event" unless @done

          Result.new(answer: @answer, sources: @sources)
        end

        private

        def consume_lines
          while (newline = @buffer.index("\n"))
            line = @buffer.slice!(0..newline).delete_suffix("\n").delete_suffix("\r")
            consume_line(line)
          end
        end

        def consume_line(line)
          if line.empty?
            dispatch
          elsif line.start_with?("event:")
            @event = line.delete_prefix("event:").strip
          elsif line.start_with?("data:")
            @data_lines << line.delete_prefix("data:").sub(/\A /, "")
          end
        end

        def dispatch
          return if @event.blank? && @data_lines.empty?

          data = @data_lines.any? ? JSON.parse(@data_lines.join("\n")) : {}
          case @event
          when "delta"
            @answer << data.fetch("content", "")
          when "reset"
            @answer.clear
          when "sources"
            @sources = Array(data["sources"])
          when "error"
            raise RequestError, data.fetch("message", "The chat stream reported an error")
          when "done"
            @done = true
          end
        rescue JSON::ParserError => e
          raise RequestError, "Chat endpoint returned invalid event JSON: #{e.message}"
        ensure
          @event = nil
          @data_lines.clear
        end
      end
    end
  end
end
