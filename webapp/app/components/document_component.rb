# frozen_string_literal: true

class DocumentComponent < ViewComponent::Base
  def initialize(presenter:, **)
    @presenter = presenter
    super()
  end

  delegate :id, to: :document
  delegate :document, to: :@presenter
end
