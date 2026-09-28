# frozen_string_literal: true

class AiSearchBarComponent < Blacklight::Component
  PLACEHOLDER = "Ask a question about people, places, themes, or documents..."
  # Questions travel in a GET URL before the chat page starts its streaming POST.
  MAX_CHARACTERS = 500

  def initialize(q: nil)
    @q = q
  end

  attr_reader :q
end
