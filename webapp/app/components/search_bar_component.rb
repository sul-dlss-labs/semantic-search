# frozen_string_literal: true

class SearchBarComponent < Blacklight::SearchBarComponent
  def default_prepend
    select_tag :search_type, options_for_select([ "keyword", "vector", "hybrid" ], params[:search_type])
  end

  def initialize(**)
    super(**)
  end
end
