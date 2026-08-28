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
    query_parameters = controller.request.query_parameters

    return url unless query_parameters.key?("canvas_index")

    "#{url}&canvas_index=#{ERB::Util.url_encode(query_parameters["canvas_index"].to_s)}"
  end
end
