# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExcerptMarkdown do
  def html(snippet)
    described_class.to_html(snippet)
  end

  it "renders bold and italics around the highlighting" do
    expect(html("**Marincovich:** the _undergraduate_ **<mark>Education</mark>** report"))
      .to eq("<strong>Marincovich:</strong> the <em>undergraduate</em> <strong><mark>Education</mark></strong> report")
  end

  it "leaves underscores inside words alone" do
    expect(html("see snake_case_word")).to eq("see snake_case_word")
  end

  it "flattens headings, paragraphs and lists onto lines of their own" do
    expect(html("## <mark>Frogs</mark> of the Valley\n\nFirst paragraph.\n\n- one\n- two"))
      .to eq("<mark>Frogs</mark> of the Valley<br>First paragraph.<br>• one<br>• two")
  end

  it "keeps the soft line breaks of OCR'd prose as spaces" do
    expect(html("line one of OCR\nline two")).to eq("line one of OCR\nline two")
  end

  it "flattens table rows into one line each, dropping the delimiter row and empty cells" do
    expect(html("Contents\n|Section|1|Methodology|\n|---|---|---|\n|Section|2|Population&lt;br&gt;<mark>Size</mark>|||"))
      .to eq("Contents<br>Section · 1 · Methodology<br>Section · 2 · Population <mark>Size</mark>")
  end

  it "keeps highlighting inside what extraction marked as code" do
    expect(html("`PHYSICAL <mark>EDUCATION</mark>`")).to eq("PHYSICAL <mark>EDUCATION</mark>")
  end

  it "drops the extractor's picture placeholders" do
    expect(html("**==&gt; picture [436 x 183] intentionally omitted &lt;==**\n\n**EUGENE A. BAUER**"))
      .to eq("<strong>EUGENE A. BAUER</strong>")
  end

  it "keeps escaped document text escaped" do
    expect(html("rights to &lt;water&gt; &amp; more")).to eq("rights to &lt;water&gt; &amp; more")
  end

  it "keeps only inline tags, without attributes" do
    output = html(%(<script>alert(1)</script><img src=x onerror=alert(1)> <a href="javascript:x">link</a> [md](http://x) <mark class="x">m</mark>))

    fragment = Nokogiri::HTML5.fragment(output)
    expect(fragment.css("*").map(&:name).uniq).to eq(%w[mark])
    expect(fragment.css("[class], [href], [src], [onerror]")).to be_empty
  end

  it "returns safe HTML" do
    expect(html("text")).to be_html_safe
  end
end
