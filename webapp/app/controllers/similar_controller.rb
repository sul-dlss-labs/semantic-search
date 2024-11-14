class SimilarController < ApplicationController
  def show
    conn = Faraday.new do |f|
       f.request :json
       f.response :json
    end

    res = conn.get("https://purl.stanford.edu/#{params[:id]}.json")
    abstract = res.body.dig('description', 'note').find { |note| note['type'] == 'abstract' }['value']
    @druids = DruidSearch.search(abstract)
    cors_set_access_control_headers
    render layout: false
  end
end
