# frozen_string_literal: true

# Solr's combined query handler is required for RRF queries. Other searches
# continue to use Blacklight's configured Solr request paths.
class CombinedQueryRepository < Blacklight::Solr::Repository
  HYBRID_PATH = "hybrid"

  # WORKAROUND(solr-combined-facets): Solr 10.1 throws an ArrayIndexOutOfBoundsException
  # when faceting a multi-valued field on combined query results. The combiner unions small
  # sub-query DocSets into a bitset sized by the highest matching doc id instead of maxDoc,
  # and per-segment facet counting then reads past its end. In practice this breaks hybrid
  # searches narrowed by a facet filter.
  #
  # Until Solr fixes this, hybrid requests are sent with facet=false and the facets come
  # from a /select request for the union of the same named queries, which matches the same
  # documents. To revert: delete this method and everything below marked
  # WORKAROUND(solr-combined-facets), plus the matching specs.
  def send_and_receive(path, solr_params = {})
    return super unless path == HYBRID_PATH && faceted?(solr_params)

    request_params = Blacklight::Solr::Request.new(solr_params.to_hash.deep_dup)
    response = super(path, request_params.merge(facet: false))
    facet_response = super(blacklight_config.solr_path, facet_request_params(request_params))
    response["facet_counts"] = facet_response["facet_counts"]
    response
  end

  private

  def default_search_path(solr_params)
    return HYBRID_PATH if solr_params[:json]&.dig(:queries).present?

    super
  end

  # WORKAROUND(solr-combined-facets)
  def faceted?(solr_params)
    ActiveModel::Type::Boolean.new.cast(solr_params[:facet])
  end

  # WORKAROUND(solr-combined-facets): a document matches a combined query when it matches
  # any of the named queries, so "should" over all of them yields the same facet counts.
  def facet_request_params(request_params)
    queries = request_params.dig(:json, :queries)
    request_params
      .except(:combiner, :"combiner.query", :"combiner.algorithm", :sort, :start)
      .merge(
        rows: 0,
        json: request_params[:json].except(:queries).merge(query: { bool: { should: queries.values } })
      )
  end
end
