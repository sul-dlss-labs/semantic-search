# frozen_string_literal: true

require "rails_helper"

RSpec.describe "query embedding instrumentation" do
  def instrument(cached:, error: nil)
    ActiveSupport::Notifications.instrument(GeminiEmbedding::QUERY_INSTRUMENTATION_EVENT, cached: cached) do
      raise error if error
    end
  end

  it "records the first lookup in the request for the results page" do
    instrument(cached: false)
    instrument(cached: true)

    expect(Current.embedding_lookup).to include(cached: false, duration_ms: a_kind_of(Float))
  end

  it "logs each lookup" do
    allow(Rails.logger).to receive(:info)

    instrument(cached: true)

    expect(Rails.logger).to have_received(:info) do |message|
      expect(JSON.parse(message)).to include("event" => "query_embedding.semantic_search",
                                             "outcome" => "success", "cached" => true)
    end
  end

  it "logs a failed lookup without recording it" do
    allow(Rails.logger).to receive(:warn)

    expect { instrument(cached: false, error: RuntimeError) }.to raise_error(RuntimeError)

    expect(Current.embedding_lookup).to be_nil
    expect(Rails.logger).to have_received(:warn) do |message|
      expect(JSON.parse(message)).to include("outcome" => "error", "error_class" => "RuntimeError")
    end
  end
end
