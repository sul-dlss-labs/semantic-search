module ApplicationHelper
  def link_to_collection(document:, value:, **)
    link_to value.first, "https://purl.stanford.edu/#{document[:collection_id_ss]}"
  end
end
