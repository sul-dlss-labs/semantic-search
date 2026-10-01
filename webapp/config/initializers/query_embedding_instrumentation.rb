# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("query_embedding.semantic_search") do |event|
  error_class = event.payload[:exception]&.first
  # The results page reports the first lookup, which is the one the catalog search made.
  Current.embedding_lookup ||= { duration_ms: event.duration, cached: event.payload[:cached] } unless error_class

  level = error_class ? :warn : :info
  Rails.logger.public_send(
    level,
    {
      event: event.name,
      outcome: error_class ? "error" : "success",
      duration_ms: event.duration.round(1),
      cached: event.payload[:cached],
      error_class: error_class
    }.compact.to_json
  )
end
