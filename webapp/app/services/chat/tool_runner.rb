# frozen_string_literal: true

require "mcp"

module Chat
  # Validates and executes the application's allowlisted MCP tools in-process.
  class ToolRunner
    MODEL_SCHEMA_KEYS = %w[
      type properties required items enum description minimum maximum minLength maxLength minItems maxItems
    ].freeze

    def initialize(controller: nil)
      @controller = controller
    end

    def definitions
      SemanticSearchMcp::Tools::ALL.map do |definition|
        {
          type: "function",
          function: {
            name: definition[:name],
            description: definition[:description],
            parameters: model_parameters(definition)
          }
        }
      end
    end

    def call(name:, arguments:)
      definition = SemanticSearchMcp::Tools::ALL.find { |candidate| candidate[:name] == name }
      return error_result("Tool not found: #{name}") unless definition

      arguments = normalized_arguments(name, arguments)
      schema = MCP::Tool::InputSchema.new(resolved_schema(definition[:input_schema]))
      schema.validate_arguments(arguments)
      handler = definition[:handler] || ->(**options) { SemanticSearchMcp::CatalogSearch.search(**options) }
      notify_tool_started(definition, arguments)

      instrument(definition, arguments) do |payload|
        result = handler.call(controller: @controller, **arguments.deep_symbolize_keys)
        result_key = definition[:logged_result_key]
        payload[:results] = Array(result.dig(:structured_content, result_key)).first(
          SemanticSearchMcp::Tools::LOGGED_RESULT_LIMIT
        ) if result_key
        payload[:tool_error] = true if result[:error]
        result
      end
    rescue MCP::Tool::InputSchema::ValidationError, JSON::ParserError => e
      error_result(e.message)
    rescue StandardError => e
      SemanticSearchMcp.internal_error("Chat tool call failed.", e)
    end

    private

    def resolved_schema(schema)
      schema.is_a?(Proc) ? schema.call : schema
    end

    def model_parameters(definition)
      schema = model_compatible_schema(resolved_schema(definition[:input_schema]))
      return schema unless definition[:name] == "catalog_search_tool"

      schema.merge(required: (Array(schema[:required]) | [ "search_type" ]))
    end

    def normalized_arguments(name, arguments)
      normalized = arguments.deep_dup
      search_type_missing = !normalized.key?("search_type") && !normalized.key?(:search_type)
      normalized["search_type"] = "vector" if name == "catalog_search_tool" && search_type_missing
      normalized
    end

    # MCP schemas remain authoritative for validation. The copy sent to the model
    # uses the JSON Schema subset accepted across LiteLLM-backed providers.
    def model_compatible_schema(value, property_map: false)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), compatible|
          next unless property_map || MODEL_SCHEMA_KEYS.include?(key.to_s)

          compatible[key] = model_compatible_schema(child, property_map: key.to_s == "properties")
        end
      when Array
        value.map { |child| model_compatible_schema(child) }
      else
        value
      end
    end

    def instrument(definition, arguments, &)
      ActiveSupport::Notifications.instrument(
        SemanticSearchMcp::Tools::INSTRUMENTATION_EVENT,
        tool_name: definition[:name],
        input: arguments.deep_dup,
        request_id: @controller&.request&.uuid,
        &
      )
    end

    def notify_tool_started(definition, arguments)
      ActiveSupport::Notifications.instrument(
        SemanticSearchMcp::Tools::START_INSTRUMENTATION_EVENT,
        tool_name: definition[:name],
        input: arguments.deep_dup,
        request_id: @controller&.request&.uuid
      )
    end

    def error_result(message)
      { text: message, structured_content: { error: message }, error: true }
    end
  end
end
