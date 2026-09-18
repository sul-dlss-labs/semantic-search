# frozen_string_literal: true

# Represents a single document returned from Solr
class SolrDocument
  include Blacklight::Solr::Document

  # self.unique_key = 'id'

  # DublinCore uses the semantic field mappings below to assemble an OAI-compliant Dublin Core document
  # Semantic mappings of solr stored fields. Fields may be multi or
  # single valued. See Blacklight::Document::SemanticFields#field_semantics
  # and Blacklight::Document::SemanticFields#to_semantic_values
  # Recommendation: Use field names from Dublin Core
  use_extension(Blacklight::Document::DublinCore)

  # The Cocina metadata for this object, as indexed in Solr.
  # @return [CocinaDisplay::CocinaRecord, nil] nil if the document has no Cocina
  def cocina_display
    @cocina_display ||= begin
      cocina_json = Array.wrap(self["cocina_ss"]).first
      CocinaDisplay::CocinaRecord.from_json(cocina_json) if cocina_json.present?
    end
  end

  delegate :abstracts, :pub_date_str, to: :cocina_display, allow_nil: true
end
