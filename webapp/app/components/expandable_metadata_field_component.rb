# frozen_string_literal: true

# Renders a Blacklight metadata field whose values can run long, clamping each value to a few
# lines behind a "Show more"/"Show less" disclosure.
#
# Wire it up per field in CatalogController, optionally overriding the clamp height:
#   config.add_index_field "abstracts", ..., component: ExpandableMetadataFieldComponent,
#                                            expandable_lines: 4
class ExpandableMetadataFieldComponent < Blacklight::MetadataFieldComponent
  DEFAULT_LINES = 4

  private

  # Unique per field, document and value, so aria-controls resolves correctly on a results page
  # rendering many documents, each of which may have several values across several expandable
  # fields. Deterministic rather than random so Turbo snapshot restore stays stable.
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
