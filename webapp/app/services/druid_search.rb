class DruidSearch
  Result = Data.define(:druid, :categories, :year)

  def self.search(query)
    embedding = GoogleEmbeddingService.embedding_for(query)
    neighbors = GoogleSearchService.neighbors(embedding)
    neighbors.map do |neighbor|
      datapoint = neighbor.datapoint
      categories = datapoint.restricts.flat_map(&:allow_list)
      year = datapoint.numeric_restricts.map(&:value_int)
      chunk_id = datapoint.datapoint_id
      druid = `jq -r '.["#{chunk_id}"].purl' semantic-search_chunk_to_doc.json`.chomp
      Result.new(druid:, categories:, year:)
    end
  end
end
