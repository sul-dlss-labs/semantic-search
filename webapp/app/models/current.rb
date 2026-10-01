# frozen_string_literal: true

# Request-scoped state, reset by Rails between requests.
class Current < ActiveSupport::CurrentAttributes
  # The first query embedding looked up in this request: { duration_ms: Float, cached: boolean }.
  # Set by config/initializers/query_embedding_instrumentation.rb.
  attribute :embedding_lookup
end
