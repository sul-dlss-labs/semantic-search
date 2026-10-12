module AiResultsHelper
  def search_results_rendered?
    controller_name == "catalog" && action_name == "index" && @response&.documents.present?
  end

  def render_ai_summary?
    search_results_rendered? && params[:q].present?
  end

  # Wider than the summary guard: a facet-only browse and a zero-result search both qualify.
  def render_ask_ai_about_results?
    controller_name == "catalog" && action_name == "index" && search_state.has_constraints?
  end

  # The search the current page represents, in a form /chat can re-run.
  def ask_ai_search_params
    search_state.to_h.except(:controller, :action)
  end

  # Filtered through Blacklight's allowlist so a link back cannot carry unaccepted params.
  def chat_search_params
    return {} if params[:search].blank?

    Blacklight::SearchState.new(
      ActionController::Parameters.new(params[:search].to_unsafe_h.symbolize_keys),
      CatalogController.blacklight_config
    ).to_h.except(:controller, :action)
  end
end
