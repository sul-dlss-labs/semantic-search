# frozen_string_literal: true

# Renders the text chunks that caused a search result to match, inside the normal Blacklight
# metadata list alongside Title/Format/Created/Collection/Abstract.
#
# The values here are Hashes supplied by the `matching_excerpts_for` helper rather than Solr
# strings, so this reads `@field.values` directly instead of `@field.render`: the usual
# rendering pipeline would run them through `to_sentence` and wrap them in microdata.
#
#   config.add_index_field "matching_excerpts", label: "Matching text",
#                          component: MatchingExcerptsComponent, expandable_lines: 6,
#                          values: ->(_config, document, view_context) {
#                            view_context.matching_excerpts_for(document)
#                          }
class MatchingExcerptsComponent < Blacklight::MetadataFieldComponent
  DEFAULT_LINES = 6

  # Raw excerpt hashes, bypassing Blacklight::Rendering::Pipeline.
  def render_field_values
    @render_field_values ||= Array.wrap(@field.values)
  end

  private

  alias_method :excerpts, :render_field_values

  # One expandable region per result; document ids are unique within a result set.
  def content_id
    "matching-excerpts-#{@field.document.id.to_s.parameterize}"
  end

  def clamp_lines
    @field.field_config.expandable_lines || DEFAULT_LINES
  end

  # "report.pdf · page 12 · chunk 3", omitting whatever the index could not supply.
  def provenance(excerpt)
    [
      excerpt[:filename],
      ("page #{excerpt[:page]}" if excerpt[:page].present?),
      ("chunk #{excerpt[:chunk_index]}" if excerpt[:chunk_index].present?)
    ].compact_blank.join(" · ")
  end

  # Visually hidden suffix distinguishing this toggle from the ~19 others on the page.
  def toggle_description
    " matching text for #{@field.document.title.presence || 'this result'}"
  end
end
