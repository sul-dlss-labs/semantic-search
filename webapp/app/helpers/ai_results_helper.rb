module AiResultsHelper
  # True on a catalog search results page that actually rendered documents.
  def search_results_rendered?
    controller_name == "catalog" && action_name == "index" && @response&.documents.present?
  end

  def render_ai_summary?
    search_results_rendered? && params[:q].present?
  end

  # Wider than the summary guard: a facet-only browse and a zero-result search are both worth
  # asking the assistant about, and neither has a query.
  def render_ask_ai_about_results?
    controller_name == "catalog" && action_name == "index" && search_state.has_constraints?
  end

  # The search the current page represents, in a form /chat can re-run.
  def ask_ai_search_params
    search_state.to_h.except(:controller, :action)
  end

  # The search params the chat page arrived with, filtered through Blacklight's own allowlist so a
  # link back to the results page cannot carry anything the catalog would not accept.
  def chat_search_params
    return {} if params[:search].blank?

    Blacklight::SearchState.new(
      ActionController::Parameters.new(params[:search].to_unsafe_h.symbolize_keys),
      CatalogController.blacklight_config
    ).to_h.except(:controller, :action)
  end

  # Plain DOM on the chat page rather than a real transcript turn, so naming the carried search
  # here costs nothing and is never replayed to the model.
  def chat_greeting
    return "What would you like to learn from the collections?" if @search_context.blank?

    if @search_context.zero_results?
      return "That search did not match anything in the catalog, but I can still search the " \
             "collections. What would you like to know?"
    end

    return "I can see ther results from your search. What would you like to know about them?" if
      @search_context.query.blank?

    "I can see the results from your search for #{@search_context.quoted_query}. " \
      "What would you like to know about them?"
  end
end
