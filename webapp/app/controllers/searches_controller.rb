class SearchesController < ApplicationController
  def show
    embedding = GoogleEmbeddingService.embedding_for(params[:q])
    neighbors = GoogleSearchService.neighbors(embedding)
    druids = neighbors.map do |neighbor|
      chunk_id = neighbor.datapoint.datapoint_id
      `jq -r '.["#{chunk_id}"].purl' semantic-search_chunk_to_doc.json`
    end.uniq

    # druids = [ 'pb340bp0996', 'kv658dm1930', 'mn938rx7215', 'rd522jf7473', 'fy040rv4004'].sample(3)
    render turbo_stream: [ turbo_stream.replace('results', partial: 'results', locals: { druids: druids }) ]
  end
end
