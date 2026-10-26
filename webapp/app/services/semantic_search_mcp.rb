# frozen_string_literal: true

require "set"

# Business logic for the Model Context Protocol integration.
module SemanticSearchMcp
  # Indexed on every child chunk: true for the metadata chunk and for chunks from world-readable
  # files, false for chunks from files only Stanford users may view.
  PUBLIC_CHUNK_FILTER = "public_bsi:true"

  def self.internal_error(message, exception)
    Rails.logger.error("#{message} #{exception.class}: #{exception.message}")
    Rails.logger.error(exception.backtrace.join("\n")) if exception.backtrace

    {
      text: message,
      structured_content: { error: message },
      error: true
    }
  end

  # Logged-in users may read every chunk. Anyone else, including a caller with no controller,
  # only gets public chunks.
  # @return [String, nil] a Solr filter query restricting child chunks, or nil for no restriction
  def self.chunk_access_filter(controller)
    PUBLIC_CHUNK_FILTER unless controller&.helpers&.authenticated?
  end
end
