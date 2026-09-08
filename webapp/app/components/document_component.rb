# frozen_string_literal: true

class DocumentComponent < ViewComponent::Base
  def initialize(presenter:, **)
    @presenter = presenter
    super()
  end

  delegate :id, to: :document
  delegate :document, to: :@presenter

  def embed_url
    url = "https://embed.stanford.edu/embed.json?hide_title=true&url=https://purl.stanford.edu/#{id}"
    return url unless canvas_index

    "#{url}&canvas_index=#{canvas_index}"
  end

  private

  # The page comes off the query string, so anything that is not a page position is dropped rather than
  # handed on to the embed service.
  def canvas_index
    value = controller.request.query_parameters["canvas_index"].to_s
    value if /\A\d+\z/.match?(value)
  end
end
