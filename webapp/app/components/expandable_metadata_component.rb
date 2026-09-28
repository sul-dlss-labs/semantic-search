# frozen_string_literal: true

# Renders a Blacklight metadata field whose values can run long, clamping each value to a few
# lines behind a "Show more"/"Show less" disclosure.
#
# Wire it up per field in CatalogController, optionally overriding the clamp height:
#   config.add_index_field "abstracts", ..., component: ExpandableMetadataComponent,
#                                            expandable_lines: 3
class ExpandableMetadataComponent < Blacklight::MetadataFieldComponent
  DEFAULT_LINES = 3

  private

  # Unique per field, document and value, so aria-controls resolves correctly on a results page
  # rendering many documents.
  def value_id(index)
    "#{@field.key.parameterize}-#{@field.document.id.parameterize}-#{index}"
  end

  # Visually hidden suffix distinguishing one of the many otherwise-identical "Show more"
  # buttons on a results page, e.g. "Show more of abstract".
  def toggle_description
    " of #{@field.label.downcase}"
  end

  def clamp_lines
    @field.field_config.expandable_lines || DEFAULT_LINES
  end
end
