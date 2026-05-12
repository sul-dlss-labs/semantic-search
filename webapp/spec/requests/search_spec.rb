require 'rails_helper'

RSpec.describe "Searches", type: :request do
  describe "GET /" do
    it "performs a keyword search" do
      get "/", params: { search_type: "keyword", search_field: "all_fields", q: "frogs" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("frogs")
      expect(response.body).to include('<option selected="selected" value="keyword">keyword</option>')
    end
  end
end
