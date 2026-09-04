# frozen_string_literal: true

module Chat
  # Runs the model/tool loop and emits browser-facing server-sent events.
  class Conversation
    DISCONNECT_ERRORS = [ IOError, Errno::EPIPE, Errno::ECONNRESET ].freeze

    InvalidMessages = MessageHistory::InvalidMessages

    def self.normalize_messages(value)
      MessageHistory.normalize(value)
    end

    def initialize(messages:, controller: nil, completion_request_factory: nil, tool_runner: nil)
      @history = MessageHistory.new(messages)
      @completion_request_factory = completion_request_factory || LiteLlmCompletionRequest.method(:new)
      @sources = SourceCollection.new
      @tool_call_executor = ToolCallExecutor.new(
        tool_runner: tool_runner || ToolRunner.new(controller: controller),
        source_collection: @sources,
        question: @history.last_user_content
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
      stream << encode_event("error", failure_for(error))
    rescue StandardError => e
      Rails.logger.info("Chat client disconnected before the error event was sent: #{e.class}: #{e.message}")
    end

    def client_disconnected?(error)
      # Puma reports its own disconnects as Puma::ConnectionError, which is not necessarily loaded
      # when this class is, so it is resolved here rather than in a constant.
      return true if defined?(Puma::ConnectionError) && error.is_a?(Puma::ConnectionError)

      DISCONNECT_ERRORS.any? { |disconnect_error| error.is_a?(disconnect_error) }
    end

    def failure_for(error)
      if error.is_a?(Net::OpenTimeout) || error.is_a?(Net::ReadTimeout)
        {
          reason: "timeout",
          message: "The chat service timed out before it could finish. Please try again, or ask a narrower question."
        }
      else
        {
          reason: "service_error",
          message: "The chat service could not complete that request. Please try again."
        }
      end
    end

    def run
      messages = @history.with_system_prompt

      Rails.configuration.x.chat.max_tool_rounds.times do
        completion, streamed_content = stream_completion(messages, tools: @tool_call_executor.definitions) do |event, data|
          yield event, data
        end
        return incomplete(completion, streamed_content:) { |event, data| yield event, data } unless completion.complete?
        return finish(completion, yield_event: ->(event, data) { yield event, data }) if completion.tool_calls.empty?

        yield "reset", {} if streamed_content.present?
        messages << completion.message
        messages.concat(@tool_call_executor.execute(completion.tool_calls) { |event, data| yield event, data })
        break if @tool_call_executor.limit_reached?
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
          tools: @tool_call_executor.definitions,
          tool_choice: "none"
        ) { |event, data| yield event, data }
        return incomplete(completion, streamed_content:) { |event, data| yield event, data } unless completion.complete?
        if completion.tool_calls.empty? && streamed_content.present?
          return finish(completion, yield_event: ->(event, data) { yield event, data })
        end

        yield "reset", {} if streamed_content.present?
      end

      empty_answer { |event, data| yield event, data }
    end

    def stream_completion(messages, tools:, tool_choice: nil)
      streamed_content = +""
      request = @completion_request_factory.call(messages:, tools:, tool_choice:)
      completion = request.stream_completion do |delta|
        streamed_content << delta
        yield "delta", content: delta
      end
      [ completion, streamed_content ]
    end

    def finish(completion, yield_event:)
      answer = completion.message["content"].to_s
      source_selection = @sources.for_answer(answer)
      linked_answer = CitationLinker.new(sources: source_selection.sources).call(answer)
      if linked_answer != answer
        yield_event.call("reset", {})
        yield_event.call(
          "sources",
          sources: source_selection.emitted_sources,
          truncated: source_selection.truncated
        )
        yield_event.call("delta", content: linked_answer)
      elsif source_selection.emitted_sources.any?
        yield_event.call(
          "sources",
          sources: source_selection.emitted_sources,
          truncated: source_selection.truncated
        )
      end
      yield_event.call("notice", message: SourceCollection::LIMIT_MESSAGE) if source_selection.truncated
      yield_event.call("done", {})
    end

    def incomplete(completion, streamed_content:)
      Rails.logger.warn("Chat response incomplete: finish_reason=#{completion.finish_reason.inspect}")
      if completion.length_limited? && streamed_content.present?
        yield "notice", message: "This response reached its length limit and may be incomplete. Please retry or ask a narrower question."
        yield "done", {}
        return
      end
      message = if completion.length_limited?
        "The response reached its length limit before it finished. Please retry or ask a narrower question."
      else
        "The response could not be completed. Please try again."
      end
      reason = completion.length_limited? ? "output_length_limit" : "incomplete_response"
      yield "error", reason:, message:
    end

    def empty_answer
      Rails.logger.warn("Chat response contained no final answer text")
      yield "error", reason: "empty_response", message: "The chat service could not produce an answer. Please try again."
    end

    def encode_event(event, data)
      "event: #{event}\ndata: #{JSON.generate(data)}\n\n"
    end
  end
end
