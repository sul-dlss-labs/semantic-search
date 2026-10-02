# frozen_string_literal: true

module Chat
  # The search a conversation was started from, with controls to drop it or any of its results.
  class SearchContextComponent < ViewComponent::Base
    def initialize(search_context:)
      @search_context = search_context
      super()
    end

    def render?
      @search_context.present?
    end
  end
end
