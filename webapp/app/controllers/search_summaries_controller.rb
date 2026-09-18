# frozen_string_literal: true

class SearchSummariesController < ApplicationController
  def create
    response.headers["Cache-Control"] = "no-store"
    context = SearchSummary.verifier.verify(params.require(:token))
    render json: { summary: SearchSummary.new(context).call }
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActionController::ParameterMissing
    render json: { error: "This search summary has expired. Reload the page to try again." }, status: :unprocessable_content
  rescue StandardError => e
    Rails.logger.error("Search summary failed: #{e.class}")
    render json: { error: "The AI summary is unavailable. Please try again." }, status: :service_unavailable
  end
end
