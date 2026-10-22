# frozen_string_literal: true

# Controller for login and logout. See the Authentication concern for the methods used below.
class AuthenticationController < ApplicationController
  # Apache requires a Shibboleth session before this action is reached.
  def login
    redirect_to after_authentication_url
  end

  # This is used by specs to allow TestShibbolethHeaders middleware to set headers.
  # This endpoint is only available in the test environment.
  def test_login
    cookies[:test_shibboleth_remote_user] = params[:remote_user]

    head :ok
  end

  def logout
    redirect_to SHIBBOLETH_LOGOUT_PATH
  end
end
