# frozen_string_literal: true

require "set"

# Business logic for the Model Context Protocol integration.
module SemanticSearchMcp
  def self.internal_error(message, exception)
    Rails.logger.error("#{message} #{exception.class}: #{exception.message}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace

    {
      text: message,
      structured_content: { error: message },
      error: true
    }
  end
end
