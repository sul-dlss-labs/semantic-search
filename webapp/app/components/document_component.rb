# frozen_string_literal: true

class DocumentComponent < ViewComponent::Base
  BASE_EMBED_URL = "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu"
  MAX_SEARCH_LENGTH = 120

  def initialize(presenter:, **)
    @presenter = presenter
    super()
  end

  delegate :id, to: :document
  delegate :document, to: :@presenter

  # Citations may arrive asking for a page (canvas_index or the more precise canvas_id) and a phrase to
  # highlight on it. Everything here is a passthrough; the phrase was already confirmed against IIIF
  # Content Search when the citation was built.
  def embed_url
    parameters = {
      "canvas_index" => canvas_index,
      "canvas_id" => canvas_id,
      "search" => search
    }.compact

    parameters.reduce("#{BASE_EMBED_URL}/#{id}") do |url, (name, value)|
      "#{url}&#{name}=#{ERB::Util.url_encode(value)}"
    end
  end

  private

  def query_parameters
    controller.request.query_parameters
  end

  def canvas_index
    value = query_parameters["canvas_index"].to_s
    value if /\A\d+\z/.match?(value)
  end

  def canvas_id
    value = query_parameters["canvas_id"].to_s
    return if value.length > MAX_SEARCH_LENGTH * 4

    uri = URI.parse(value)
    value if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  def search
    value = query_parameters["search"].to_s.gsub(/[[:cntrl:]]/, "").strip
    value if value.present? && value.length <= MAX_SEARCH_LENGTH
  end
end
