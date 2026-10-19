# frozen_string_literal: true

class SkipLinkComponent < Blacklight::SkipLinkComponent
  def search_id
    "#search-bar"
  end

  # The documentation page has no search bar to skip to.
  def link_to_search
    super unless helpers.controller_name == "documentation"
  end
end
