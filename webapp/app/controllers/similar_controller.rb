class SimilarController < ApplicationController
  def show
    conn = Faraday.new do |f|
       f.request :json
       f.response :json
    end

    res = conn.get("https://purl.stanford.edu/#{params[:id]}.json")
    abstract = res.body.dig('description', 'note').find { |note| note['type'] == 'abstract' }['value']
    @druids = DruidSearch.search(abstract)
    render layout: false
    # render html: "#{druids[0..3]}"
  end
end
