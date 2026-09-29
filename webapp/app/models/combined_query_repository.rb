# frozen_string_literal: true

# Solr's combined query handler is required for RRF queries. Other searches
# continue to use Blacklight's configured Solr request paths.
class CombinedQueryRepository < Blacklight::Solr::Repository
  private

  def default_search_path(solr_params)
    return "hybrid" if solr_params.to_hash.dig(:json, :queries).present?

    super
  end
end
