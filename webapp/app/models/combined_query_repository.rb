# frozen_string_literal: true

# Solr's combined query handler is required for RRF queries. Other searches
# continue to use Blacklight's configured Solr request paths.
class CombinedQueryRepository < Blacklight::Solr::Repository
  HYBRID_PATH = "hybrid"

  private

  def default_search_path(solr_params)
    return HYBRID_PATH if solr_params[:json]&.dig(:queries).present?

    super
  end
end
