# frozen_string_literal: true

class DocumentComponent < ViewComponent::Base
  # Params that sul-embed will honor if we pass them
  EMBED_PARAMS = %w[filename page canvas_index].freeze

  def initialize(presenter:, **)
    @presenter = presenter
    super()
  end

  delegate :id, to: :document
  delegate :document, to: :@presenter

  def embed_url
    url = "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/#{id}"

    viewer_parameters.empty? ? url : "#{url}&#{viewer_parameters.to_query}"
  end

  private

  # Send both page and canvas_index; we don't know what viewer sul-embed will
  # use, so we do both. Extra params don't harm anything.
  def viewer_parameters
    embed_params.tap do |params|
      params["canvas_index"] ||= canvas_index
    end.compact_blank
  end

  # Params we're going to forward on to the embed viewer for deep linking
  def embed_params
    @embed_params ||= controller
      .request.query_parameters.slice(*EMBED_PARAMS)
      .select { |_name, value| value.is_a?(String) && value.present? }
  end

  # One-based, used for PDF viewer
  # @return [Integer, nil]
  def page_number
    embed_params["page"]&.to_i
  end

  # Zero-based, used for Mirador viewer (e.g. for books)
  # @return [Integer, nil]
  def canvas_index
    (page_number - 1) if page_number&.positive?
  end
end
