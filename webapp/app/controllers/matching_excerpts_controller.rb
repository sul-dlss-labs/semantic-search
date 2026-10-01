# frozen_string_literal: true

# Loads the matching excerpts for a page of search results after the page itself has rendered,
# so the grouped excerpt query never delays the results. The page leaves an empty placeholder
# for each result and a lazy turbo-frame pointing here; this responds with Turbo Stream actions
# that fill each placeholder in, or remove it when the result has no matching text.
#
# The frame request only accepts HTML, so the Turbo Stream format is forced: Turbo applies any
# response it fetched that carries the Turbo Stream content type, frame loads included.
class MatchingExcerptsController < ApplicationController
  include Blacklight::Configurable

  copy_blacklight_config_from(CatalogController)

  # Matches Blacklight's default max_per_page.
  MAX_DOCUMENTS = 100
  DOCUMENT_FIELDS = %w[id doc_type_ssi title_display_tesi title_tesi title_tsim
                       chunk_text_tesi filename_ss page_ss chunk_index_i].freeze

  # Answers with streams for every requested id, even on failure, so no result is left showing
  # a loading skeleton.
  def index
    @placeholders = ids.map { |id| SolrDocument.new(id: id) }
    @documents, @matching_excerpts = documents_and_excerpts

    render formats: :turbo_stream, content_type: Mime[:turbo_stream]
  end

  private

  def documents_and_excerpts
    found = documents.index_by(&:id)
    excerpts = MatchingExcerpts.new(documents: found.values, query: query, search_type: search_type,
                                    embedding: embedding).call
    [ found, excerpts ]
  rescue StandardError => e
    Rails.logger.warn("Matching excerpts unavailable: #{e.class}: #{e.message}")
    [ {}, {} ]
  end

  def query
    params[:q].to_s
  end

  # The same classification CatalogController applied to the search that rendered the page.
  def search_type
    @search_type ||= CatalogSearchClassifier.new(query).call if query.present?
  end

  # Reuses the embedding the catalog search just cached, so this does not call LiteLLM again.
  def embedding
    return if query.blank? || search_type == "keyword"

    GeminiEmbedding.query_embedding(query)
  rescue StandardError => e
    # Keyword clauses alone still find excerpts for hybrid searches.
    Rails.logger.warn("Matching excerpts embedding unavailable: #{e.class}: #{e.message}")
    nil
  end

  # The documents are looked up rather than taken from the page, so the excerpts are drawn only
  # from what is in the index.
  def ids
    @ids ||= Array(params[:ids]).map(&:to_s).compact_blank.uniq.first(MAX_DOCUMENTS).reject { |id| id.include?(",") }
  end

  def documents
    return [] if ids.empty? || query.blank?

    blacklight_config.repository.search(params: {
      q: "{!terms f=id}#{ids.join(',')}",
      fl: DOCUMENT_FIELDS.join(","),
      rows: ids.length,
      facet: false
    }).documents
  end

  # @return [Array<Hash>] the matching excerpts for one result; never nil
  def matching_excerpts_for(document)
    @matching_excerpts.fetch(document.id, [])
  end
  helper_method :matching_excerpts_for
end
