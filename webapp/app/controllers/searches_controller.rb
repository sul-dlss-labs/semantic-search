class SearchesController < ApplicationController
  def show
    druids = DruidSearch.search(params[:q])
    render turbo_stream: [ turbo_stream.replace('results', partial: 'results', locals: { druids: druids }) ]
  end
end
