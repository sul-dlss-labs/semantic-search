class SearchesController < ApplicationController
  def show
    results = DruidSearch.search(params[:q])
    render turbo_stream: [ turbo_stream.replace('results', partial: 'results', locals: { results: results }) ]
  end
end
