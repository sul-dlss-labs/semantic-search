# frozen_string_literal: true

class SkipLinkComponent < Blacklight::SkipLinkComponent
  # Blacklight aims this at the query input, but that input is inside the panel Ask AI hides.
  # The search landmark wraps both modes and carries its own accessible name, so arriving there
  # is announced rather than silent.
  def search_id
    "#search-bar"
  end
end
