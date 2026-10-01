# frozen_string_literal: true

# Renders a matching-text excerpt, which is a fragment of the Markdown that text extraction
# produced (bold speaker names, headings, OCR'd tables), as inline HTML.
#
# An excerpt is cut out of the middle of a document, so its block structure is incomplete and
# would render badly: a heading or half a table inside a quote. Commonmarker renders the inline
# formatting, block boundaries become line breaks, and only inline tags survive.
#
# The input is Solr's highlighted fragment: source text already HTML-escaped, with <mark> around
# the matched terms. Those are the only raw tags, and they pass through as inline HTML.
module ExcerptMarkdown
  ALLOWED_TAGS = %w[strong em mark br].freeze

  # Pdf extraction's placeholders for images, e.g. "**==> picture [436 x 183] intentionally omitted <==**".
  PICTURE_PLACEHOLDER = /\**==&gt;.*?&lt;==\**/m
  # Line breaks inside table cells arrive as literal, escaped <br> tags.
  ESCAPED_BREAK = /&lt;br\s*\/?&gt;/i
  # Underlined text arrives wrapped in literal, escaped <u> tags. Underlines read as links, so
  # they are dropped rather than rendered.
  ESCAPED_UNDERLINE = /&lt;\/?u&gt;/i
  TABLE_DELIMITER_ROW = /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)*\|?\s*$\n?/
  BLOCK_END = %r{</(?:p|h[1-6]|li|blockquote|pre|tr)>|<hr\s*/?>}

  OPTIONS = {
    render: { unsafe: true, hardbreaks: false },
    # Tables are flattened beforehand; header ids would add anchor links; autolinked URLs would
    # be stripped by the sanitizer anyway.
    extension: { table: false, header_ids: nil, autolink: false, tagfilter: false }
  }.freeze

  extend self

  # @param snippet [String] an escaped, highlighted excerpt
  # @return [ActiveSupport::SafeBuffer]
  def to_html(snippet)
    html = Commonmarker.to_html(preprocess(snippet.to_s), options: OPTIONS)
    html = html.gsub(/<li>/, "<li>• ").gsub(BLOCK_END, "<br>")
    html = sanitizer.sanitize(html, tags: ALLOWED_TAGS, attributes: [])
    html.gsub(%r{(?:\s*<br>\s*)+}, "<br>").delete_prefix("<br>").delete_suffix("<br>").strip.html_safe
  end

  private

  def preprocess(snippet)
    snippet
      .gsub(PICTURE_PLACEHOLDER, "")
      .gsub(ESCAPED_BREAK, " ")
      .gsub(ESCAPED_UNDERLINE, "")
      # Extraction marks OCR'd columns as code. A code span would show <mark> as literal text.
      .delete("`")
      .gsub(TABLE_DELIMITER_ROW, "")
      .lines.map { |line| line.include?("|") ? table_row(line) : line }.join
  end

  # "|Section|1|Methodology|" becomes "Section · 1 · Methodology", as a paragraph of its own so
  # that each row gets its own line rather than running into the next.
  def table_row(line)
    cells = line.strip.split(/\s*\|+\s*/).compact_blank
    "\n#{cells.join(' · ')}\n\n"
  end

  def sanitizer
    @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
  end
end
