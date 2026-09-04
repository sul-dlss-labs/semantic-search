# frozen_string_literal: true

require "json"

module Chat
  # Executes model-requested tools and returns messages suitable for the next completion.
  class ToolCallExecutor
    def initialize(tool_runner:, source_collection:, question:, result_compactor: nil)
      @tool_runner = tool_runner
      @source_collection = source_collection
      @question = question
      @call_count = 0
      @discovery_performed = false
      @result_compactor = result_compactor || ToolResultCompactor.new(
        character_budget: Rails.configuration.x.chat.max_evidence_characters
      )
    end

    delegate :definitions, to: :@tool_runner

    def limit_reached?
      @call_count >= Rails.configuration.x.chat.max_tool_calls
    end

    def execute(tool_calls)
      tool_calls.map do |tool_call|
        if limit_reached?
          limit_message(tool_call)
        else
          execute_tool_call(tool_call) { |event, data| yield event, data }
        end
      end
    end

    private

    def execute_tool_call(tool_call)
      @call_count += 1
      name = tool_call.dig("function", "name")
      yield "status", message: "Searching the corpus…"
      result = call_tool(name, tool_call.dig("function", "arguments"))
      @source_collection.add(result[:structured_content]) unless result[:error]
      {
        "role" => "tool",
        "tool_call_id" => tool_call["id"],
        "content" => @result_compactor.call(result)
      }
    end

    def limit_message(tool_call)
      {
        "role" => "tool",
        "tool_call_id" => tool_call["id"],
        "content" => "The tool-call limit has been reached. Use the evidence already returned."
      }
    end

    def call_tool(name, raw_arguments)
      arguments = JSON.parse(raw_arguments.presence || "{}")
      return deterministic_discovery(name, arguments) if initial_discovery?(name)

      @tool_runner.call(name:, arguments:)
    rescue JSON::ParserError => e
      { text: "Invalid tool arguments: #{e.message}", structured_content: { error: e.message }, error: true }
    end

    def initial_discovery?(name)
      !@discovery_performed && DeterministicDiscovery.handles?(name)
    end

    def deterministic_discovery(requested_name, requested_arguments)
      @discovery_performed = true
      DeterministicDiscovery.new(tool_runner: @tool_runner).call(
        query: @question,
        requested_name:,
        requested_arguments:
      )
    end
  end
end
