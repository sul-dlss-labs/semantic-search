# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::MessageHistory do
  before do
    allow(Rails.configuration.x.chat).to receive(:max_message_characters).and_return(10)
    allow(Rails.configuration.x.chat).to receive(:max_history_messages).and_return(3)
    allow(Rails.configuration.x.chat).to receive(:max_history_characters).and_return(15)
  end

  it "normalizes and bounds submitted messages" do
    messages = [
      { role: "user", content: "discarded" },
      { role: "assistant", content: "1234567890extra" },
      { role: "user", content: "abcdefghijextra" }
    ]

    expect(described_class.normalize(messages)).to eq(
      [
        { "role" => "user", "content" => "abcdefghij" }
      ]
    )
  end

  it "provides completion-ready history and the current question" do
    allow(Rails.configuration.x.chat).to receive(:max_message_characters).and_return(100)
    allow(Rails.configuration.x.chat).to receive(:system_prompt).and_return("Use the corpus.")
    history = described_class.new([ { role: "user", content: "Which frog?" } ])

    expect(history.with_system_prompt).to eq(
      [
        { "role" => "system", "content" => "Use the corpus." },
        { "role" => "user", "content" => "Which frog?" }
      ]
    )
    expect(history.last_user_content).to eq("Which frog?")
  end

  it "rejects history that does not end with a user message" do
    expect { described_class.new([ { role: "assistant", content: "Hello" } ]) }
      .to raise_error(described_class::InvalidMessages, "The last message must be from the user.")
  end
end
