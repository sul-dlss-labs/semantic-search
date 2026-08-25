# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("start.mcp_tool") do |event|
  payload = event.payload
  Rails.logger.info(
    {
      event: event.name,
      tool_name: payload[:tool_name],
      input: payload[:input],
      request_id: payload[:request_id]
    }.compact.to_json
  )
end

ActiveSupport::Notifications.subscribe("call.mcp_tool") do |event|
  payload = event.payload
  error_class = payload[:exception]&.first
  log_data = {
    event: event.name,
    outcome: error_class || payload[:tool_error] ? "error" : "success",
    duration_ms: event.duration.round(1),
    tool_name: payload[:tool_name],
    input: payload[:input],
    results: payload[:results],
    request_id: payload[:request_id],
    error_class: error_class
  }.compact

  level = error_class || payload[:tool_error] ? :warn : :info
  Rails.logger.public_send(level, log_data.to_json)
end
