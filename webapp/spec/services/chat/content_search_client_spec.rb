# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::ContentSearchClient do
  subject(:client) { described_class.new(base: "https://contentsearch.example") }

  let(:http) { instance_double(Net::HTTP) }
  let(:druid) { "fr576hr0294" }
  let(:canvas) { "https://purl.stanford.edu/#{druid}/iiif/canvas/one" }

  before do
    allow(Net::HTTP).to receive(:new).with("contentsearch.example", 443).and_return(http)
    allow(http).to receive(:use_ssl=).with(true)
    allow(http).to receive(:open_timeout=).with(2)
    allow(http).to receive(:read_timeout=).with(3)
  end

  def respond(body, response_class: Net::HTTPOK, &verify)
    response = response_class.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return(body)
    allow(http).to receive(:request) do |request|
      verify&.call(request)
      response
    end
  end

  it "sends a quoted phrase query and returns the distinct canvas ids it matched" do
    body = {
      resources: [
        { on: "#{canvas}#xywh=1,2,3,4" },
        { on: "#{canvas}#xywh=5,6,7,8" }
      ]
    }.to_json
    respond(body) do |request|
      expect(request.uri.to_s).to eq(
        "https://contentsearch.example/#{druid}/search?q=%22calendar+of+campus%22"
      )
    end

    expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to eq([ canvas ])
  end

  it "returns an empty list when the phrase matches nothing" do
    respond({ resources: [] }.to_json)

    expect(client.canvas_ids(druid:, phrase: "no such phrase")).to eq([])
  end

  it "returns nil when the service errors, so the caller does not cache a failure as a miss" do
    allow(http).to receive(:request).and_raise(Net::ReadTimeout)

    expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to be_nil
  end

  it "returns nil for a non-success response" do
    respond("", response_class: Net::HTTPInternalServerError)

    expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to be_nil
  end

  it "returns nil for an unparseable body" do
    respond("not json")

    expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to be_nil
  end

  it "makes no request for an identifier that is not a druid" do
    expect(Net::HTTP).not_to receive(:new)

    expect(client.canvas_ids(druid: "../../etc/passwd", phrase: "calendar")).to be_nil
  end

  it "makes no request for a blank phrase" do
    expect(Net::HTTP).not_to receive(:new)

    expect(client.canvas_ids(druid:, phrase: " ")).to be_nil
  end

  describe "caching" do
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    it "looks a phrase up once per object" do
      respond({ resources: [ { on: canvas } ] }.to_json)

      expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to eq([ canvas ])
      expect(client.canvas_ids(druid:, phrase: "calendar of campus")).to eq([ canvas ])
      expect(http).to have_received(:request).once
    end

    it "caches a miss, which is a valid answer" do
      respond({ resources: [] }.to_json)

      expect(client.canvas_ids(druid:, phrase: "absent")).to eq([])
      expect(client.canvas_ids(druid:, phrase: "absent")).to eq([])
      expect(http).to have_received(:request).once
    end
  end
end
