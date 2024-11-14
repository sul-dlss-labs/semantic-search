class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  protect_from_forgery unless: -> { request.method == 'OPTIONS' }

  def cors_preflight_check
      # if request.method == 'OPTIONS' && request.origin&.match?(/\Ahttps:\/\/[^\\]+\.stanford.edu\//)
        cors_set_access_control_headers
        head :ok
      # end
    end

  protected

  def cors_set_access_control_headers
      response.headers['Access-Control-Allow-Origin'] = "*"
      # response.headers['Access-Control-Allow-Credentials'] = "true"
      # response.headers['Access-Control-Allow-Methods'] = 'POST, GET, PUT, PATCH, DELETE, OPTIONS'
      # response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept'
      # response.headers['Access-Control-Max-Age'] = '86400'
  end
end
