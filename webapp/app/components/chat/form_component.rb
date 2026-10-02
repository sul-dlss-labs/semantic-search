# frozen_string_literal: true

module Chat
  class FormComponent < ViewComponent::Base
    PLACEHOLDER = "Ask a question about people, places, themes, or documents..."

    def initialize(question:, search_context: nil)
      @question = question
      @search_context = search_context
      super()
    end

    attr_reader :question, :search_context

    def max_characters
      Rails.configuration.x.chat.max_message_characters
    end
  end
end
