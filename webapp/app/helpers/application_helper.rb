module ApplicationHelper
  def link_to_collection(document:, value:, **)
    link_to value.first, "https://purl.stanford.edu/#{document[:collection_id_ss]}"
  end

  def publication_date(document:, **)
    document.publication_date
  end

  def abstracts(document:, **)
    document.abstracts.presence || "no abstract provided"
  end
end
