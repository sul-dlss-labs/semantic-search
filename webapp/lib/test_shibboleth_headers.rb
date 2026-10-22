# frozen_string_literal: true

# This is a Rack middleware that we use in testing. It injects headers
# that simulate mod_shib so we can test.
# This is added to the test environment configuration in config/environments/test.rb.
class TestShibbolethHeaders
  def initialize(app)
    @app = app
  end

  def call(env)
    # The /test_login endpoint sets a cookie that provides the value for the header.
    # Tests call /test_login via the sign_in() helper method before a test.
    request = Rack::Request.new(env)
    if request.cookies["test_shibboleth_remote_user"]
      env[mangle(Authentication::REMOTE_USER_HEADER)] = request.cookies["test_shibboleth_remote_user"]
    end

    @app.call(env)
  end

  # Transform the header key into the format that Rack expects.
  def mangle(key)
    "HTTP_#{key.upcase.tr('-', '_')}"
  end
end
