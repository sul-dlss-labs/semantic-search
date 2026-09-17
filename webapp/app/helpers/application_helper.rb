module ApplicationHelper
  def link_to_collection(document:, value:, **)
    link_to value.first, "https://purl.stanford.edu/#{document[:collection_id_ss]}"
  end

  def pub_date_str(document:, **)
    document.pub_date_str
  end

  def abstracts(document:, **)
    document.abstracts.presence || "no abstract provided"
  end
end
