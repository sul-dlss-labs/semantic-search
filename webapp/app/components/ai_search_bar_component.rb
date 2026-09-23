# frozen_string_literal: true

# The Ask AI half of the navbar search bar: a single question field that hands off to the chat
# assistant. It submits GET /chat?q=… rather than posting, because POST /chat is the SSE streaming
# endpoint; the chat page prefills the question from :q and starts the conversation on load.
class AiSearchBarComponent < Blacklight::Component
  PLACEHOLDER = "Ask a question about our collections"

  # A GET puts the question in the request line, so it is capped well below the chat page's own
  # 8000-character limit.
  MAX_CHARACTERS = 500

  # Carrying the current query keeps the text in place when the user flips between the two modes.
  def initialize(q: nil)
    @q = q
  end

  attr_reader :q
end
