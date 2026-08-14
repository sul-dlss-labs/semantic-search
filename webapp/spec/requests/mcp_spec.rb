# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP endpoint", type: :request do
  let(:solr_connection) { instance_double(RSolr::Client) }
  let(:empty_solr_response) do
    {
      "responseHeader" => { "status" => 0, "params" => {} },
      "response" => { "numFound" => 0, "start" => 0, "docs" => [] }
    }
  end
  let(:solr_response) { empty_solr_response }

  before do
    allow(RSolr).to receive(:connect).and_return(solr_connection)
    allow(solr_connection).to receive(:send_and_receive).and_return(solr_response)
  end

  describe "POST /mcp" do
    def post_mcp(body)
      post "/mcp", params: body.to_json, headers: { "Content-Type" => "application/json" }
    end

    it "lists the catalog search tool and supported search types" do
      post_mcp(jsonrpc: "2.0", id: "1", method: "tools/list")

      expect(response).to have_http_status(:ok)
      tools = response.parsed_body.dig("result", "tools")
      expect(tools.pluck("name")).to eq([ "catalog_search_tool" ])
      expect(tools.first.dig("inputSchema", "properties", "search_type", "enum"))
        .to eq(%w[keyword vector hybrid])
      expect(tools.first.dig("inputSchema", "properties", "filters", "properties")).to include(
        "format",
        "format_hsim"
      )
    end

    it "performs a keyword search" do
      post_mcp(
        jsonrpc: "2.0",
        id: "2",
        method: "tools/call",
        params: {
          name: "catalog_search_tool",
          arguments: { query: "frogs", search_type: "keyword" }
        }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).not_to be true
      expect(result.dig("content", 0, "text")).to include("No results found for query: frogs")
      expect(result.dig("structuredContent", "search_type")).to eq("keyword")
    end

    it "defaults to hybrid search" do
      embedding = instance_double(GeminiEmbedding, embedding: [ [ 0.1, 0.2 ] ])
      allow(GeminiEmbedding).to receive(:new).and_return(embedding)

      post_mcp(
        jsonrpc: "2.0",
        id: "3",
        method: "tools/call",
        params: { name: "catalog_search_tool", arguments: { query: "frogs" } }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).not_to be true
      expect(result.dig("structuredContent", "search_type")).to eq("hybrid")
      expect(embedding).to have_received(:embedding).with(
        input: [ "frogs" ],
        instruction: GeminiEmbedding::DEFAULT_QUERY_INSTRUCTION
      )
    end

    it "performs a vector search" do
      embedding = instance_double(GeminiEmbedding, embedding: [ [ 0.1, 0.2 ] ])
      allow(GeminiEmbedding).to receive(:new).and_return(embedding)

      post_mcp(
        jsonrpc: "2.0",
        id: "4",
        method: "tools/call",
        params: {
          name: "catalog_search_tool",
          arguments: { query: "frogs", search_type: "vector" }
        }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).not_to be true
      expect(result.dig("structuredContent", "search_type")).to eq("vector")
      expect(embedding).to have_received(:embedding)
    end

    it "applies catalog facet filters" do
      post_mcp(
        jsonrpc: "2.0",
        id: "5",
        method: "tools/call",
        params: {
          name: "catalog_search_tool",
          arguments: {
            query: "maps",
            search_type: "keyword",
            filters: { collection: "Stanford Digital Repository" }
          }
        }
      )

      expect(response).to have_http_status(:ok)
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).not_to be true
      expect(result.dig("content", 0, "text")).to include(
        "with filters (collection: Stanford Digital Repository)"
      )
    end

    context "when Solr returns a document" do
      let(:solr_response) do
        {
          "responseHeader" => { "status" => 0, "params" => {} },
          "response" => {
            "numFound" => 1,
            "start" => 0,
            "docs" => [
              {
                "id" => "abc123",
                "title_display_tesi" => "A frog map",
                "author_person_ssim" => [ "Jane Stanford" ],
                "doc_type_ssi" => "Image",
                "collection_title_ss" => "Map Collection",
                "child_count_i" => 2
              }
            ]
          }
        }
      end

      it "returns application-specific metadata and a catalog URL" do
        post_mcp(
          jsonrpc: "2.0",
          id: "6",
          method: "tools/call",
          params: {
            name: "catalog_search_tool",
            arguments: { query: "frogs", search_type: "keyword" }
          }
        )

        result = response.parsed_body.dig("result", "structuredContent", "results", 0)
        expect(result).to include(
          "id" => "abc123",
          "title" => "A frog map",
          "authors" => [ "Jane Stanford" ],
          "format" => "Image",
          "collection" => "Map Collection",
          "child_count" => 2,
          "url" => "http://www.example.com/catalog/abc123"
        )
      end
    end
  end
end
