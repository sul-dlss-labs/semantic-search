# frozen_string_literal: true

require "digest"
require "json"
require "net/http"

module Chat
  # Looks up a phrase in an object's IIIF Content Search service.
  #
  # Phrase queries must be quoted: an unquoted multi-word query is an OR query and matches hundreds of
  # incidental words. The service answers 200 with an empty resource list when nothing matches, including
  # for objects that have no OCR at all.
  class ContentSearchClient
    DEFAULT_BASE = "https://contentsearch.stanford.edu"
    DRUID = /\A[a-z]{2}\d{3}[a-z]{2}\d{4}\z/
    HIT_TTL = 12.hours
    MISS_TTL = 1.hour
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3

    def initialize(base: ENV.fetch("CONTENT_SEARCH_BASE", DEFAULT_BASE))
      @base = base.chomp("/")
    end

    # @return [Array<String>] canvas ids the phrase occurs on, empty when it occurs nowhere
    # @return [nil] when the service could not be reached or understood
    def canvas_ids(druid:, phrase:)
      return nil if phrase.blank?
      return nil unless DRUID.match?(druid.to_s)

      key = cache_key(druid, phrase)
      cached = Rails.cache.read(key)
      return cached unless cached.nil?

      canvas_ids = request_canvas_ids(druid, phrase)
      return nil if canvas_ids.nil?

      Rails.cache.write(key, canvas_ids, expires_in: canvas_ids.any? ? HIT_TTL : MISS_TTL)
      canvas_ids
    end

    private

    def cache_key(druid, phrase)
      [ "contentsearch", druid, Digest::SHA256.hexdigest(phrase.downcase) ].join(":")
    end

    def request_canvas_ids(druid, phrase)
      uri = URI("#{@base}/#{druid}/search")
      uri.query = URI.encode_www_form(q: %("#{phrase}"))

      response = get(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      resources = JSON.parse(response.body)["resources"]
      Array(resources).filter_map { |resource| resource["on"]&.split("#")&.first }.uniq
    rescue JSON::ParserError, Timeout::Error, SystemCallError, SocketError, Net::HTTPBadResponse,
           Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Content search failed for #{druid}: #{e.class}: #{e.message}")
      nil
    end

    def get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      http.request(Net::HTTP::Get.new(uri))
    end
  end
end
