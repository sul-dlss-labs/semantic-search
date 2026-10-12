# frozen_string_literal: true

class ChatsController < ApplicationController
  def show
    render locals: {
      search_context: Chat::SearchContext.from_search_params(params[:search], controller: self),
      question: submitted_question
    }
  end

  def create
    submitted_messages = params.require(:messages)
    raise Chat::Conversation::InvalidMessages, "Messages must be an array." unless submitted_messages.respond_to?(:map)

    messages = Chat::Conversation.normalize_messages(
      submitted_messages.map { |message| message.respond_to?(:to_unsafe_h) ? message.to_unsafe_h : message }
    )
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache, no-store"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Last-Modified"] = Time.current.httpdate
    self.response_body = Chat::Conversation.new(
      messages:, controller: self, search_context: search_context_from_token
    ).each_event
  rescue ActionController::ParameterMissing, Chat::Conversation::InvalidMessages => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def submitted_question
    params[:q].to_s.strip.first(Rails.configuration.x.chat.max_message_characters).presence
  end

  # An unreadable token drops the context rather than failing the turn.
  def search_context_from_token
    Chat::SearchContext.from_token(
      params[:context_token], excluded_ids: excluded_document_ids, controller: self
    )
  end

  # Dropped results ride alongside the signed token rather than re-signing one per removal, which
  # is safe because an id can only subtract a document the token already carries.
  def excluded_document_ids
    ids = params[:excluded_ids]
    ids.is_a?(Array) ? ids.grep(String) : []
  end
end
