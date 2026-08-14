# frozen_string_literal: true

require "mcp"

# HTTP interface for Model Context Protocol functionality.
class McpController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_default_response_format

  def index
    render json: mcp_server.handle_json(request.body.read)
  rescue StandardError => e
    Rails.logger.error "MCP Error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      jsonrpc: "2.0",
      id: nil,
      error: {
        code: -32603,
        message: "Internal error: #{e.message}"
      }
    }, status: :internal_server_error
  end

  private

  def set_default_response_format
    request.format = :json unless params[:format]
  end

  def mcp_server
    configuration = MCP::Configuration.new(protocol_version: "2025-03-26")
    MCP::Server.new(
      name: "semantic-search",
      version: "1.0.0",
      instructions: "Use this tool to search Stanford Libraries digital collections using keyword, vector, or hybrid search.",
      tools: [ catalog_tool ],
      server_context: {
        controller: self,
        request_id: request.uuid
      },
      configuration: configuration
    )
  end

  def catalog_tool
    definition = SemanticSearchMcp::Tools::CATALOG_SEARCH
    schema = definition[:input_schema]

    Class.new(MCP::Tool).tap do |tool|
      tool.tool_name definition[:name]
      tool.description definition[:description]
      tool.input_schema(schema.is_a?(Proc) ? schema.call : schema)
      tool.define_singleton_method(:call) do |**arguments|
        context = arguments.delete(:server_context)
        result = SemanticSearchMcp::CatalogSearch.search(controller: context&.dig(:controller), **arguments)
        MCP::Tool::Response.new(
          [ { type: "text", text: result[:text] } ],
          structured_content: result[:structured_content],
          error: result[:error] || false
        )
      end
    end
  end
end
