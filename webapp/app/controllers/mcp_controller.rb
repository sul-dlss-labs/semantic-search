# frozen_string_literal: true

require "mcp"

# HTTP interface for Model Context Protocol functionality.
class McpController < ApplicationController
  skip_before_action :verify_authenticity_token

  TOOL_LIST_TTL_MS = 5.minutes.in_milliseconds

  def index
    status, headers, body = mcp_transport.handle_request(request)
    headers.each { |name, value| response.set_header(name, value) }
    self.status = status
    self.response_body = body
  end

  private

  def mcp_transport
    MCP::Server::Transports::StreamableHTTPTransport.new(
      mcp_server,
      stateless: true,
      allowed_hosts: ENV.fetch("MCP_ALLOWED_HOSTS", "").split(",").map(&:strip).compact_blank
    )
  end

  def mcp_server
    capabilities = MCP::Server::Capabilities.new.tap(&:support_tools)
    configuration = MCP::Configuration.new(validate_tool_call_results: true)
    MCP::Server.new(
      name: "semantic-search",
      version: "1.0.0",
      instructions: "Search Stanford Libraries digital collections. Use catalog_search_tool to find documents, " \
                    "get_document_chunks to read a known document (following cursors until complete when an exhaustive scan is required), " \
                    "and search_passages to find semantically relevant passages across documents.",
      tools: SemanticSearchMcp::Tools::ALL.map { |definition| mcp_tool(definition) },
      server_context: {
        controller: self,
        request_id: request.uuid
      },
      capabilities: capabilities,
      configuration: configuration,
      ttl_ms: TOOL_LIST_TTL_MS,
      cache_scope: "public"
    )
  end

  def mcp_tool(definition)
    input_schema = definition[:input_schema]
    output_schema = definition[:output_schema]

    Class.new(MCP::Tool).tap do |tool|
      tool.tool_name definition[:name]
      tool.description definition[:description]
      tool.input_schema(input_schema.is_a?(Proc) ? input_schema.call : input_schema)
      tool.output_schema(output_schema.is_a?(Proc) ? output_schema.call : output_schema) if output_schema
      tool.annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
      tool.define_singleton_method(:call) do |**arguments|
        context = arguments.delete(:server_context)
        handler = definition[:handler] || ->(**options) { SemanticSearchMcp::CatalogSearch.search(**options) }
        ActiveSupport::Notifications.instrument(
          SemanticSearchMcp::Tools::START_INSTRUMENTATION_EVENT,
          tool_name: definition[:name],
          input: arguments.deep_dup,
          request_id: context&.dig(:request_id)
        )
        ActiveSupport::Notifications.instrument(
          SemanticSearchMcp::Tools::INSTRUMENTATION_EVENT,
          tool_name: definition[:name],
          input: arguments.deep_dup,
          request_id: context&.dig(:request_id)
        ) do |payload|
          result = handler.call(controller: context&.dig(:controller), **arguments)
          result_key = definition[:logged_result_key]
          payload[:results] = Array(result.dig(:structured_content, result_key)).first(
            SemanticSearchMcp::Tools::LOGGED_RESULT_LIMIT
          ) if result_key
          payload[:tool_error] = true if result[:error]

          MCP::Tool::Response.new(
            [ { type: "text", text: result[:text] } ],
            structured_content: result[:structured_content],
            error: result[:error] || false
          )
        end
      end
    end
  end
end
