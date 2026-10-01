# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"

module Chat
  module Evaluation
    # Exercises the deployed chat endpoint through the same HTTP interface as a browser.
    class RemoteChatClient
      # The server sends this notice, then a done event, when the model hits its output token limit.
      LENGTH_LIMIT_NOTICE = "reached its length limit"

      Result = Data.define(:answer, :sources, :notices) do
        def initialize(answer:, sources:, notices: [])
          super
        end

        def truncated?
          notices.any? { |notice| notice.to_s.include?(LENGTH_LIMIT_NOTICE) }
        end
      end

      class RequestError < StandardError; end

      def initialize(base_url:)
        @base_uri = URI(base_url)
        raise ArgumentError, "CHAT_EVAL_TARGET_URL must use http or https" unless %w[http https].include?(@base_uri.scheme)

        @base_uri.path = "/" if @base_uri.path.blank?
      end

      # search_context is a hash of Blacklight search params, resolved into a signed token by the
      # deployment itself, which is the only side holding secret_key_base.
      def ask(question, history: [], search_context: nil)
        csrf_token, cookies, context_token = fetch_session(search_context)
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
        body = { messages: }
        body[:context_token] = context_token if context_token.present?
        request.body = body.to_json

        perform(uri, request) do |response|
          raise_request_error(response) unless response.is_a?(Net::HTTPSuccess)

          response.read_body { |chunk| accumulator.feed(chunk) }
        end
        accumulator.finish
      end

      private

      def fetch_session(search_context = nil)
        uri = endpoint_uri(search_context)
        request = Net::HTTP::Get.new(uri, "Accept" => "text/html")
        response = perform(uri, request)
        raise_request_error(response) unless response.is_a?(Net::HTTPSuccess)

        body = response.body.to_s
        token = body[/<meta\s+[^>]*name=["']csrf-token["'][^>]*content=["']([^"']+)["'][^>]*>/i, 1]
        raise RequestError, "The chat page did not contain a CSRF token" if token.blank?

        cookies = Array(response.get_fields("set-cookie")).filter_map { |cookie| cookie.split(";", 2).first }.join("; ")
        [ CGI.unescapeHTML(token), cookies, context_token_from(body, search_context) ]
      end

      # Fails loudly: an unscoped conversation would look like a model regression.
      def context_token_from(body, search_context)
        return nil if search_context.blank?

        token = body[/<input[^>]*name=["']context_token["'][^>]*value=["']([^"']+)["']/i, 1]
        token ||= body[/<input[^>]*value=["']([^"']+)["'][^>]*name=["']context_token["']/i, 1]
        raise RequestError, "The chat page did not carry a search context for #{search_context.inspect}" if token.blank?

        CGI.unescapeHTML(token)
      end

      def endpoint_uri(search_context = nil)
        uri = URI.join(@base_uri.to_s.end_with?("/") ? @base_uri.to_s : "#{@base_uri}/", "chat")
        uri.query = { search: search_context }.to_query if search_context.present?
        uri
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
          @notices = []
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

          Result.new(answer: @answer, sources: @sources, notices: @notices)
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
          when "notice"
            @notices << data.fetch("message", "")
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
