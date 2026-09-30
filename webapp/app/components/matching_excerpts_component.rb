# frozen_string_literal: true

# Renders the text chunks that caused a search result to match, inside the normal Blacklight
# metadata list alongside Title/Format/Created/Collection/Abstract.
#
# The values here are Hashes supplied by the `matching_excerpts_for` helper rather than Solr
# strings, so this reads `@field.values` directly instead of `@field.render`: the usual
# rendering pipeline would run them through `to_sentence` and wrap them in microdata.
#
# The results page renders it with the PENDING value, as a label and skeleton; the excerpts
# themselves are rendered in their place by MatchingExcerptsController.
#
#   config.add_index_field "matching_excerpts", label: "Matching text",
#                          component: MatchingExcerptsComponent, expandable_lines: 6,
#                          values: ->(_config, document, view_context) {
#                            view_context.try(:matching_excerpts_for, document)
#                          }
class MatchingExcerptsComponent < Blacklight::MetadataFieldComponent
  DEFAULT_LINES = 6
  PENDING = :pending

  # The id of the placeholder <dd> that the asynchronously loaded excerpts replace.
  def self.slot_id(document)
    "matching-excerpts-slot-#{document.id.to_s.parameterize}"
  end

  # The id of the placeholder's "Matching text:" <dt>.
  def self.label_id(document)
    "matching-excerpts-label-#{document.id.to_s.parameterize}"
  end

  # Raw excerpt hashes, bypassing Blacklight::Rendering::Pipeline.
  def render_field_values
    @render_field_values ||= Array.wrap(@field.values)
  end

  private

  def pending?
    render_field_values == [ PENDING ]
  end

  alias_method :excerpts, :render_field_values

  # One expandable region per result; document ids are unique within a result set.
  def content_id
    "matching-excerpts-#{@field.document.id.to_s.parameterize}"
  end

  def clamp_lines
    @field.field_config.expandable_lines || DEFAULT_LINES
  end

  # "report.pdf · page 12", omitting whatever the index could not supply. The chunk index is an
  # indexing detail with no meaning to users, so it is not shown.
  def provenance(excerpt)
    location = [
      excerpt[:filename],
      ("page #{excerpt[:page]}" if excerpt[:page].present?)
    ].compact_blank.join(" · ")
    location.present? ? link_to(location, record_path(excerpt)) : location
  end

  # Links to the record's page here, opening its viewer at the excerpt's page, the same way chat
  # citations do (chat_controller.js#citationUrl): DocumentComponent passes canvas_index on to the
  # embed, and canvases are numbered from zero.
  def record_path(excerpt)
    page = excerpt[:page].to_s
    canvas_index = (page.to_i - 1 if page.match?(/\A\d+\z/) && page.to_i.positive?)
    helpers.solr_document_path(record_id, { canvas_index: }.compact)
  end

  # Child chunks surfaced as results carry ids like "bb191qg8085_report_pdf_c4".
  def record_id
    @field.document.id.to_s.split("_", 2).first
  end

  # Visually hidden suffix distinguishing this toggle from the ~19 others on the page.
  def toggle_description
    " matching text for #{@field.document.title.presence || 'this result'}"
  end
end
