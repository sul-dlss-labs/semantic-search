# frozen_string_literal: true

class AiSearchBarComponent < Blacklight::Component
  PLACEHOLDER = "Ask a question about people, places, themes, or documents..."
  # Questions travel in a GET URL before the chat page starts its streaming POST.
  MAX_CHARACTERS = 500

  def initialize(q: nil, search_params: {})
    @q = q
    @search_params = search_params || {}
  end

  attr_reader :q, :search_params

  # Flipping the Search/Ask AI toggle on a results page submits this form, which would otherwise
  # drop the search the user is looking at without them ever leaving the page.
  def search_param_fields
    flatten_params("search", search_params)
  end

  private

  def flatten_params(prefix, value)
    case value
    when Hash then value.flat_map { |key, nested| flatten_params("#{prefix}[#{key}]", nested) }
    when Array then value.flat_map { |nested| flatten_params("#{prefix}[]", nested) }
    else [ [ prefix, value.to_s ] ]
    end
  end
end
