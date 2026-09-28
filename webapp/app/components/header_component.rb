# frozen_string_literal: true

class HeaderComponent < Blacklight::HeaderComponent
  def before_render
    with_top_bar unless top_bar
    with_search_bar(component: SearchNavbarComponent) unless search_bar
  end
end
