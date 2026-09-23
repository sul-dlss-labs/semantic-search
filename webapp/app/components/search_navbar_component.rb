# frozen_string_literal: true

# Wraps Blacklight's search bar in a Search / Ask AI toggle. Both forms are always in the DOM;
# CSS :has() on the checked radio decides which one is visible, so the swap needs no JavaScript.
class SearchNavbarComponent < Blacklight::SearchNavbarComponent
  # Once the user is in the chat interface, Ask AI is the honest starting state for the toggle.
  def ai_mode?
    helpers.controller_name == "chats"
  end

  # Same arguments Blacklight passes, minus its default col-md-12 col-lg-8 sizing, which fights the
  # flex row the toggle shares with the form.
  def search_bar_component
    search_bar_component_class.new(
      url: helpers.search_action_url,
      advanced_search_url: helpers.search_action_url(action: "advanced_search"),
      params: helpers.search_state.params_for_search.except(:qt),
      autocomplete_path: suggest_index_catalog_path,
      classes: %w[search-query-form]
    )
  end
end
