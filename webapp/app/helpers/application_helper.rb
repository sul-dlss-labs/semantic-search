module ApplicationHelper
  def link_to_collection(document:, value:, **)
    link_to value.first, document[:collection_url_ss]
  end
end
