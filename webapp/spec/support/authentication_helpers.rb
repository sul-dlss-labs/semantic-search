# frozen_string_literal: true

# Helpers to assist with authentication.
module AuthenticationHelpers
  def authentication_headers_for(remote_user)
    { Authentication::REMOTE_USER_HEADER => remote_user }
  end

  def sign_in(remote_user = "user@stanford.edu", example: RSpec.current_example)
    if example.metadata[:type] == :system
      visit test_login_path(remote_user:)
    else
      get test_login_path(remote_user:)
    end
  end

  RSpec.configure do |config|
    config.include AuthenticationHelpers, type: :system
    config.include AuthenticationHelpers, type: :request
  end
end
