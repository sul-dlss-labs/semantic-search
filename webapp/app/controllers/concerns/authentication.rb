# frozen_string_literal: true

# Concern for handling authentication via Shibboleth (copied from the approach used in argo-b3).
#
# Apache is configured so that:
# - /webauth/login requires a shibboleth authenticated user. Thus, redirecting a user to it triggers login.
# - /Shibboleth.sso/Logout logs the user out of shibboleth.
# - Other pages do not require authentication.
# - It provides the X-Remote-User request header when the user is authenticated.
module Authentication
  extend ActiveSupport::Concern

  MAX_URL_SIZE = ActionDispatch::Cookies::MAX_COOKIE_SIZE / 2
  SHIBBOLETH_LOGOUT_PATH = "/Shibboleth.sso/Logout"

  REMOTE_USER_HEADER = "X-Remote-User"

  included do
    helper_method :authenticated?
  end

  private

  # @return [Boolean] true if Shibboleth has authenticated the user making this request.
  def authenticated?
    remote_user.present?
  end

  # In development there is no Apache in front of Rails, so set REMOTE_USER to simulate a login.
  def remote_user
    return ENV.fetch("REMOTE_USER", nil) if Rails.env.development?

    request.headers[REMOTE_USER_HEADER]
  end

  # Use as a before_action in controllers whose actions require a logged in user.
  def require_authentication
    request_authentication unless authenticated?
  end

  def request_authentication
    # Always check that we have enough space in the cookie to store the full return URL.
    #
    # This situation typically occurs when we are scanned for vulnerabilities and a
    # CRLF Injection attack is attempted, see https://www.geeksforgeeks.org/crlf-injection-attack/
    session[:return_to_after_authenticating] = request.url if request.url.size < MAX_URL_SIZE
    redirect_to main_app.login_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end
end
