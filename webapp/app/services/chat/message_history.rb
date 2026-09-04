# frozen_string_literal: true

module Chat
  # Validates and bounds the user-visible messages supplied to a conversation.
  class MessageHistory
    class InvalidMessages < StandardError; end

    def self.normalize(value)
      messages = Array(value).map do |message|
        raise InvalidMessages, "Each message must have a valid role and content." unless message.respond_to?(:to_h)

        message = message.to_h.stringify_keys
        role = message["role"]
        content = message["content"]
        raise InvalidMessages, "Each message must have a valid role and content." unless %w[user assistant].include?(role)
        raise InvalidMessages, "Each message must have a valid role and content." unless content.is_a?(String) && content.present?

        { "role" => role, "content" => content.first(max_message_characters) }
      end
      raise InvalidMessages, "Enter a message to start chatting." if messages.empty?
      raise InvalidMessages, "The last message must be from the user." unless messages.last["role"] == "user"

      trim_to_character_limit(messages.last(max_history_messages))
    end

    def self.max_message_characters
      Rails.configuration.x.chat.max_message_characters
    end

    def self.max_history_messages
      Rails.configuration.x.chat.max_history_messages
    end

    def self.trim_to_character_limit(messages)
      limit = Rails.configuration.x.chat.max_history_characters
      kept = []
      characters = 0
      messages.reverse_each do |message|
        break if characters + message["content"].length > limit && kept.any?

        kept << message
        characters += message["content"].length
      end
      kept.reverse
    end
    private_class_method :max_message_characters, :max_history_messages, :trim_to_character_limit

    def initialize(messages)
      @messages = self.class.normalize(messages)
    end

    def with_system_prompt
      [ { "role" => "system", "content" => Rails.configuration.x.chat.system_prompt } ] + @messages
    end

    def last_user_content
      @messages.last.fetch("content")
    end
  end
end
