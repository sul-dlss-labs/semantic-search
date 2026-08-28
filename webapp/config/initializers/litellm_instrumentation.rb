# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("request.litellm") do |event|
  payload = event.payload
  error_class = payload[:exception]&.first
  log_data = {
    event: event.name,
    outcome: error_class ? "error" : "success",
    duration_ms: event.duration.round(1),
    model: payload[:model],
    operation: payload[:operation],
    input_count: payload[:input_count],
    input_characters: payload[:input_characters],
    instruction_present: payload[:instruction_present],
    dimensions: payload[:dimensions],
    http_status: payload[:http_status],
    request_id: payload[:request_id],
    response_id: payload[:response_id],
    prompt_tokens: payload[:prompt_tokens],
    completion_tokens: payload[:completion_tokens],
    total_tokens: payload[:total_tokens],
    finish_reason: payload[:finish_reason],
    stream_complete: payload[:stream_complete],
    error_class: error_class
  }.compact

  level = error_class ? :warn : :info
  Rails.logger.public_send(level, log_data.to_json)
end
