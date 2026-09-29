# frozen_string_literal: true

class SearchBarComponent < Blacklight::SearchBarComponent
  def initialize(params:, **)
    super(params: params.except(:search_type), **)
  end

  # Submit button is text only; the magnifying glass comes from
  # .search-btn::before rather than Blacklight's inline SVG icon.
  def default_search_button
    tag.button(class: "btn btn-primary search-btn", type: "submit", id: "#{@prefix}search",
               aria: { label: scoped_t("submit") }) do
      tag.span(scoped_t("submit"), class: "submit-search-text")
    end
  end
end
