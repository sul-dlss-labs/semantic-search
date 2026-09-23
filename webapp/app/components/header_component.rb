# frozen_string_literal: true

class HeaderComponent < Blacklight::HeaderComponent
  # Redeclaring `renders_one :search_bar` here would raise RedefinedSlotError, since ViewComponent
  # clones the parent's registered slots into subclasses. Swapping the default through the slot
  # lambda's `component:` argument is the supported way to substitute our own navbar.
  def before_render
    with_top_bar unless top_bar
    with_search_bar(component: SearchNavbarComponent) unless search_bar
  end
end
