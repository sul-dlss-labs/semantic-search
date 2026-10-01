# frozen_string_literal: true

class SearchNavbarComponent < Blacklight::SearchNavbarComponent
  def ai_mode?
    helpers.controller_name == "chats"
  end

  # The search in view, or on the chat page the one it arrived with, so a fresh question keeps it.
  def ai_search_params
    return helpers.chat_search_params if ai_mode?

    helpers.render_ask_ai_about_results? ? helpers.ask_ai_search_params : {}
  end

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
