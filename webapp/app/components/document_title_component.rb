# frozen_string_literal: true

# Drops Blacklight 9's default `h5` class from result titles so the SUL component
# style library's h3 type scale applies instead of its (much smaller) h5 scale.
class DocumentTitleComponent < Blacklight::DocumentTitleComponent
  def initialize(classes: "index_title document-title-heading col", **)
    super(classes:, **)
  end
end
