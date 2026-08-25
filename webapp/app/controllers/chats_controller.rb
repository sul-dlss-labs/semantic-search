# frozen_string_literal: true

class ChatsController < ApplicationController
  def show; end

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
    self.response_body = Chat::Conversation.new(messages:, controller: self).each_event
  rescue ActionController::ParameterMissing, Chat::Conversation::InvalidMessages => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
