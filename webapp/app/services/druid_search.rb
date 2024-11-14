class DruidSearch
  def self.search(query)
    embedding = GoogleEmbeddingService.embedding_for(query)
    neighbors = GoogleSearchService.neighbors(embedding)
    neighbors.map do |neighbor|
      chunk_id = neighbor.datapoint.datapoint_id
      `jq -r '.["#{chunk_id}"].purl' semantic-search_chunk_to_doc.json`
    end.map(&:chomp).uniq
  end
end
