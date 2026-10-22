# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "GET /webauth/login" do
    it "redirects to the root" do
      get "/webauth/login", headers: authentication_headers_for("user@stanford.edu")

      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /webauth/logout" do
    it "redirects to the shibboleth logout" do
      get "/webauth/logout", headers: authentication_headers_for("user@stanford.edu")

      expect(response).to redirect_to(Authentication::SHIBBOLETH_LOGOUT_PATH)
    end
  end

  describe "#authenticated?" do
    let(:controller) { ApplicationController.new }

    before do
      controller.request = ActionDispatch::TestRequest.create
    end

    it "is false without the remote user header" do
      expect(controller.send(:authenticated?)).to be false
    end

    it "is true with the remote user header" do
      controller.request.headers[Authentication::REMOTE_USER_HEADER] = "user@stanford.edu"

      expect(controller.send(:authenticated?)).to be true
    end
  end

  describe "header links" do
    it "shows a login link when not authenticated" do
      get "/documentation"

      page = Nokogiri::HTML(response.body)
      expect(page.css('header a[href="/webauth/login"]').map(&:text)).to eq %w[Login Login]
      expect(page.css('header a[href="/webauth/logout"]')).to be_empty
    end

    it "shows a logout link when authenticated" do
      sign_in

      get "/documentation"

      page = Nokogiri::HTML(response.body)
      expect(page.css('header a[href="/webauth/logout"]').map(&:text)).to eq %w[Logout Logout]
      expect(page.css('header a[href="/webauth/login"]')).to be_empty
    end
  end

  describe "sign_in" do
    it "makes later requests authenticated" do
      sign_in

      get "/webauth/login"
      expect(request.headers[Authentication::REMOTE_USER_HEADER]).to eq "user@stanford.edu"
    end
  end
end
