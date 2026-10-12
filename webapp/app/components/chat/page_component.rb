# frozen_string_literal: true

module Chat
  # The chat page: an optional carried search context, the transcript, and the question form.
  class PageComponent < ViewComponent::Base
    # @param search_context [Chat::SearchContext, nil] the search the conversation was started from
    # @param search_params [Hash] the search the page arrived with, whether or not it could be rebuilt
    # @param question [String, nil] a question submitted from the search bar, sent on page load
    def initialize(search_context: nil, search_params: {}, question: nil)
      @search_context = search_context
      @search_params = search_params || {}
      @submitted_question = question
      super()
    end

    attr_reader :search_context, :search_params

    # A suggested question is only prefilled, so arriving here never spends a model call.
    def autostart?
      @submitted_question.present?
    end

    def question
      @submitted_question || search_context&.suggested_question
    end

    # Lets the page explain a search it could not rebuild instead of silently dropping it.
    def search_context_unavailable?
      search_params.present? && search_context.nil?
    end

    def greeting
      return "What would you like to learn from the collections?" if search_context.blank?

      if search_context.zero_results?
        return "That search did not match anything in the catalog, but I can still search the " \
               "collections. What would you like to know?"
      end

      return "I can see the results from your search. What would you like to know about them?" if
        search_context.query.blank?

      "I can see the results from your search for #{search_context.quoted_query}. " \
        "What would you like to know about them?"
    end
  end
end
