# frozen_string_literal: true

class AskAiSelectComponent < Blacklight::Component
  def initialize(document:, action: nil, **)
    @document = document
    @action = action
    super()
  end

  def render?
    helpers.render_ask_ai_about_results?
  end

  def key
    @action&.key || :ask_ai_select
  end

  def input_id
    "ask-ai-select-#{@document.id.to_s.parameterize}"
  end

  def label
    "Select #{helpers.document_presenter(@document).heading} for Ask AI"
  end
end
