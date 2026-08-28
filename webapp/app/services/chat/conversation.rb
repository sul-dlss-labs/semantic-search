# frozen_string_literal: true

module Chat
  # Runs the model/tool loop and emits browser-facing server-sent events.
  class Conversation
    DISCOVERY_TOOL_NAMES = %w[catalog_search_tool search_passages].freeze
    DISCONNECT_ERRORS = [ IOError, Errno::EPIPE, Errno::ECONNRESET ].freeze

    class InvalidMessages < StandardError; end

    def self.normalize_messages(value)
      messages = Array(value).map do |message|
        raise InvalidMessages, "Each message must have a valid role and content." unless message.respond_to?(:to_h)

        message = message.to_h.stringify_keys
        role = message["role"]
        content = message["content"]
        raise InvalidMessages, "Each message must have a valid role and content." unless %w[user assistant].include?(role)
        raise InvalidMessages, "Each message must have a valid role and content." unless content.is_a?(String) && content.present?

        { "role" => role, "content" => content.first(max_message_characters) }
      end
      raise InvalidMessages, "Enter a message to start chatting." if messages.empty?
      raise InvalidMessages, "The last message must be from the user." unless messages.last["role"] == "user"

      messages = messages.last(max_history_messages)
      trim_to_character_limit(messages)
    end

    def self.max_message_characters
      Rails.configuration.x.chat.max_message_characters
    end

    def self.max_history_messages
      Rails.configuration.x.chat.max_history_messages
    end

    def self.trim_to_character_limit(messages)
      limit = Rails.configuration.x.chat.max_history_characters
      kept = []
      characters = 0
      messages.reverse_each do |message|
        break if characters + message["content"].length > limit && kept.any?

        kept << message
        characters += message["content"].length
      end
      kept.reverse
    end

    def initialize(messages:, controller: nil, client: LiteLlmClient.new, tool_runner: nil)
      @history = self.class.normalize_messages(messages)
      @client = client
      @tool_runner = tool_runner || ToolRunner.new(controller: controller)
      @sources = []
      @tool_call_count = 0
      @discovery_performed = false
      @tool_result_compactor = ToolResultCompactor.new(
        character_budget: Rails.configuration.x.chat.max_evidence_characters
      )
    end

    def each_event
      Enumerator.new do |stream|
        run { |event, data| stream << encode_event(event, data) }
      rescue StandardError => e
        report_failure(stream, e)
      end
    end

    private

    # The browser is written to from inside this enumerator, so a hangup surfaces as an exception
    # from whatever the loop happened to be doing. There is nobody left to tell in that case, and
    # writing the error event would just raise again.
    def report_failure(stream, error)
      if client_disconnected?(error)
        Rails.logger.info("Chat client disconnected mid-stream: #{error.class}: #{error.message}")
        return
      end

      Rails.logger.error("Chat request failed: #{error.class}: #{error.message}")
      stream << encode_event("error", message: "The chat service could not complete that request. Please try again.")
    rescue StandardError => e
      Rails.logger.info("Chat client disconnected before the error event was sent: #{e.class}: #{e.message}")
    end

    def client_disconnected?(error)
      # Puma reports its own disconnects as Puma::ConnectionError, which is not necessarily loaded
      # when this class is, so it is resolved here rather than in a constant.
      return true if defined?(Puma::ConnectionError) && error.is_a?(Puma::ConnectionError)

      DISCONNECT_ERRORS.any? { |disconnect_error| error.is_a?(disconnect_error) }
    end

    def run
      messages = [ { "role" => "system", "content" => Rails.configuration.x.chat.system_prompt } ] + @history

      Rails.configuration.x.chat.max_tool_rounds.times do
        completion, streamed_content = stream_completion(messages, tools: @tool_runner.definitions) do |event, data|
          yield event, data
        end
        return incomplete(completion) { |event, data| yield event, data } unless completion.complete?
        return finish(completion, yield_event: ->(event, data) { yield event, data }) if completion.tool_calls.empty?

        yield "reset", {} if streamed_content.present?
        messages << completion.message
        execute_tool_calls(completion.tool_calls, messages) { |event, data| yield event, data }
        break if @tool_call_count >= Rails.configuration.x.chat.max_tool_calls
      end

      messages << {
        "role" => "system",
        "content" => "Stop searching and answer now using only the evidence already returned. If it is insufficient, say so."
      }
      2.times do |attempt|
        messages << {
          "role" => "system",
          "content" => "Return a final answer as plain response text now. Do not call a tool."
        } if attempt.positive?
        completion, streamed_content = stream_completion(
          messages,
          tools: @tool_runner.definitions,
          tool_choice: "none"
        ) { |event, data| yield event, data }
        return incomplete(completion) { |event, data| yield event, data } unless completion.complete?
        if completion.tool_calls.empty? && streamed_content.present?
          return finish(completion, yield_event: ->(event, data) { yield event, data })
        end

        yield "reset", {} if streamed_content.present?
      end

      empty_answer { |event, data| yield event, data }
    end

    def stream_completion(messages, tools:, tool_choice: nil)
      streamed_content = +""
      completion = @client.stream_completion(messages:, tools:, tool_choice:) do |delta|
        streamed_content << delta
        yield "delta", content: delta
      end
      [ completion, streamed_content ]
    end

    def execute_tool_calls(tool_calls, messages)
      tool_calls.each do |tool_call|
        if @tool_call_count >= Rails.configuration.x.chat.max_tool_calls
          messages << {
            "role" => "tool",
            "tool_call_id" => tool_call["id"],
            "content" => "The tool-call limit has been reached. Use the evidence already returned."
          }
          next
        end

        @tool_call_count += 1
        name = tool_call.dig("function", "name")
        yield "status", message: "Searching the corpus…"
        result = call_tool(name, tool_call.dig("function", "arguments"))
        collect_sources(result[:structured_content]) unless result[:error]
        messages << {
          "role" => "tool",
          "tool_call_id" => tool_call["id"],
          "content" => @tool_result_compactor.call(result)
        }
      end
    end

    def call_tool(name, raw_arguments)
      arguments = JSON.parse(raw_arguments.presence || "{}")
      return deterministic_discovery(name, arguments) if initial_discovery?(name)

      @tool_runner.call(name:, arguments:)
    rescue JSON::ParserError => e
      { text: "Invalid tool arguments: #{e.message}", structured_content: { error: e.message }, error: true }
    end

    def initial_discovery?(name)
      !@discovery_performed && DISCOVERY_TOOL_NAMES.include?(name)
    end

    def deterministic_discovery(requested_name, requested_arguments)
      @discovery_performed = true
      query = @history.last.fetch("content")
      searches = [
        [ "search_passages", { "query" => query } ],
        [ "catalog_search_tool", { "query" => query, "search_type" => "vector", "rows" => 10 } ]
      ]
      requested_search = [ requested_name, requested_arguments ]
      searches << requested_search unless searches.include?(requested_search)

      combine_discovery_results(searches.map do |name, arguments|
        [ name, @tool_runner.call(name:, arguments:) ]
      end)
    end

    def combine_discovery_results(searches)
      successful = searches.reject { |_name, result| result[:error] }
      structured_content = successful.each_with_object({ passages: [], results: [] }) do |(_name, result), content|
        result_content = result[:structured_content].to_h.deep_symbolize_keys
        content[:passages].concat(Array(result_content[:passages]))
        content[:results].concat(Array(result_content[:results]))
      end
      text = searches.map do |name, result|
        "#{name}:\n#{result[:text]}"
      end.join("\n\n")

      { text:, structured_content:, error: successful.empty? }
    end

    def collect_sources(content)
      return unless content.is_a?(Hash)

      content = content.deep_symbolize_keys
      candidates = Array(content[:results]).map do |result|
        { title: result[:title], url: result[:url], pages: pages_from(result[:matched_chunks]) }
      end
      candidates.concat(
        Array(content[:passages]).map do |passage|
          {
            title: passage[:document_title] || passage[:document_id] || "Catalog record",
            url: passage[:url],
            pages: pages_from([ passage ])
          }
        end
      )
      if content[:document_id] && content[:url]
        candidates << {
          title: "Document #{content[:document_id]}",
          url: content[:url],
          pages: pages_from(content[:chunks])
        }
      end

      candidates.each do |candidate|
        next if candidate[:title].blank? || candidate[:url].blank?

        existing_source = @sources.find { |source| source[:url] == candidate[:url] }
        if existing_source
          merge_pages(existing_source, candidate[:pages])
          next
        end

        source = { title: candidate[:title], url: candidate[:url] }
        source[:pages] = candidate[:pages] if candidate[:pages].any?
        @sources << source
      end
    end

    def pages_from(chunks)
      Array(chunks).flat_map { |chunk| Array(chunk[:page]) }.compact_blank.map(&:to_s).uniq
    end

    def merge_pages(source, pages)
      return if pages.empty?

      source[:pages] = (Array(source[:pages]) + pages).uniq
    end

    def finish(completion, yield_event:)
      sources = @sources.first(10)
      answer = completion.message["content"].to_s
      linked_answer = CitationLinker.new(sources:).call(answer)
      if linked_answer != answer
        yield_event.call("reset", {})
        yield_event.call("sources", sources:)
        yield_event.call("delta", content: linked_answer)
      elsif sources.any?
        yield_event.call("sources", sources:)
      end
      yield_event.call("done", {})
    end

    def incomplete(completion)
      Rails.logger.warn("Chat response incomplete: finish_reason=#{completion.finish_reason.inspect}")
      message = if completion.length_limited?
        "The response reached its length limit before it finished. Please retry or ask a narrower question."
      else
        "The response could not be completed. Please try again."
      end
      yield "error", message: message
    end

    def empty_answer
      Rails.logger.warn("Chat response contained no final answer text")
      yield "error", message: "The chat service could not produce an answer. Please try again."
    end

    def encode_event(event, data)
      "event: #{event}\ndata: #{JSON.generate(data)}\n\n"
    end
  end
end
