class SearchesController < ApplicationController
  def show
    druids = [ 'pb340bp0996', 'kv658dm1930', 'mn938rx7215', 'rd522jf7473', 'fy040rv4004'].sample(3)
    render turbo_stream: [ turbo_stream.replace('results', partial: 'results', locals: { druids: druids }) ]
  end
end
