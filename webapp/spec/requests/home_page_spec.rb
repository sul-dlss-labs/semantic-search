require 'rails_helper'

RSpec.describe "Home page", type: :request do
  it "renders the search modes over the hero image, without facets" do
    get "/"

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".home-hero .search-modes")).to be_present
    expect(page.at_css(page.at_css(".home-more-info")["data-bs-target"])).to be_present
    expect(page.at_css(".navbar-search, #sidebar")).to be_nil
    expect(page.at_css(".safari-notice")).to be_nil
  end

  it "keeps the navbar search and facets once a search is in view" do
    get "/", params: { search_field: "all_fields", f: { format_hsim: [ "Text" ] } }

    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".navbar-search .search-modes")).to be_present
    expect(page.at_css("#sidebar")).to be_present
    expect(page.at_css(".home-hero")).to be_nil
  end
end
