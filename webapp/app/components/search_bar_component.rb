# frozen_string_literal: true

class SearchBarComponent < Blacklight::SearchBarComponent
  # The values are read by SearchBuilder; only the labels are display text.
  SEARCH_TYPES = [ [ "Keyword", "keyword" ], [ "Vector", "vector" ], [ "Hybrid", "hybrid" ] ].freeze

  def initialize(**)
    super(**)
  end

  # A borderless .form-select.search-field at the head of the input group.
  def default_prepend
    safe_join([
      label_tag(:search_type, "Search using", class: "visually-hidden"),
      select_tag(:search_type,
                 options_for_select(SEARCH_TYPES, params[:search_type]),
                 title: "Search type options",
                 class: "form-select search-field")
    ])
  end

  # Submit button is text only; the magnifying glass comes from
  # .search-btn::before rather than Blacklight's inline SVG icon.
  def default_search_button
    tag.button(class: "btn btn-primary search-btn", type: "submit", id: "#{@prefix}search",
               aria: { label: scoped_t("submit") }) do
      tag.span(scoped_t("submit"), class: "submit-search-text")
    end
  end

  # The prepended select always sits to the left of the query input, so the input
  # never has rounded leading corners.
  def rounded_border_class
    "rounded-0"
  end
end
