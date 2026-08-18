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

    def capture_mcp_events
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(SemanticSearchMcp::Tools::INSTRUMENTATION_EVENT) do |event|
        events << event
      end
      yield
      events
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it "lists the search and document-reading tools" do
      post_mcp(jsonrpc: "2.0", id: "1", method: "tools/list")

      expect(response).to have_http_status(:ok)
      tools = response.parsed_body.dig("result", "tools")
      expect(tools.pluck("name")).to eq(%w[catalog_search_tool get_document_chunks search_passages])
      catalog_tool = tools.find { |tool| tool["name"] == "catalog_search_tool" }
      expect(catalog_tool.dig("inputSchema", "properties", "search_type", "enum"))
        .to eq(%w[keyword vector hybrid])
      expect(catalog_tool.dig("inputSchema", "properties", "filters", "properties")).to include(
        "format",
        "format_hsim"
      )
      expect(tools).to all(include("annotations" => include("readOnlyHint" => true, "destructiveHint" => false)))
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

    it "instruments catalog search input and at most the first 10 results" do
      results = 11.times.map { |index| { id: "document-#{index}" } }
      allow(SemanticSearchMcp::CatalogSearch).to receive(:search).and_return(
        text: "Found 11 results",
        structured_content: { results: results }
      )

      events = capture_mcp_events do
        post_mcp(
          jsonrpc: "2.0",
          id: "instrument-catalog",
          method: "tools/call",
          params: {
            name: "catalog_search_tool",
            arguments: { query: "frogs", search_type: "keyword", rows: 11 }
          }
        )
      end

      expect(events.length).to eq(1)
      expect(events.first.payload).to include(
        tool_name: "catalog_search_tool",
        input: { query: "frogs", search_type: "keyword", rows: 11 },
        results: results.first(10),
        request_id: be_present
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

      it "returns the vector-matched chunks for each result" do
        embedding = instance_double(GeminiEmbedding, embedding: [ [ 0.1, 0.2 ] ])
        allow(GeminiEmbedding).to receive(:new).and_return(embedding)
        matched_chunk_response = {
          "responseHeader" => { "status" => 0, "params" => {} },
          "response" => {
            "numFound" => 1,
            "start" => 0,
            "docs" => [
              {
                "id" => "abc123_file_c4",
                "chunk_text_tesi" => "The passage about frogs and maps.",
                "filename_ss" => "transcript.pdf",
                "chunk_index_i" => 4,
                "score" => 0.91
              }
            ]
          }
        }
        allow(solr_connection).to receive(:send_and_receive).and_return(solr_response, matched_chunk_response)

        post_mcp(
          jsonrpc: "2.0",
          id: "7",
          method: "tools/call",
          params: {
            name: "catalog_search_tool",
            arguments: { query: "frogs", search_type: "vector" }
          }
        )

        result = response.parsed_body.fetch("result")
        chunks = result.dig("structuredContent", "results", 0, "matched_chunks")
        expect(chunks).to eq(
          [
            {
              "text" => "The passage about frogs and maps.",
              "filename" => "transcript.pdf",
              "chunk_index" => 4,
              "score" => 0.91
            }
          ]
        )
        expect(result.dig("content", 0, "text")).to include(
          "Matched chunks:",
          "(transcript.pdf, chunk 4) The passage about frogs and maps."
        )
      end
    end

    describe "get_document_chunks" do
      let(:solr_response) do
        {
          "responseHeader" => { "status" => 0, "params" => {} },
          "response" => {
            "numFound" => 2,
            "start" => 0,
            "docs" => [
              {
                "id" => "abc123_transcript_c0",
                "chunk_text_tesi" => "The first passage.",
                "filename_ss" => "transcript.pdf",
                "chunk_index_i" => 0
              }
            ]
          }
        }
      end

      it "returns ordered chunks and a continuation cursor" do
        events = capture_mcp_events do
          post_mcp(
            jsonrpc: "2.0",
            id: "8",
            method: "tools/call",
            params: {
              name: "get_document_chunks",
              arguments: { document_id: "abc123", limit: 1 }
            }
          )
        end

        result = response.parsed_body.fetch("result")
        structured = result.fetch("structuredContent")
        expect(structured).to include(
          "document_id" => "abc123",
          "total_chunks" => 2,
          "returned_chunks" => 1,
          "complete" => false,
          "url" => "http://www.example.com/catalog/abc123"
        )
        expect(structured.fetch("next_cursor")).to be_present
        expect(structured.fetch("chunks")).to eq(
          [
            {
              "id" => "abc123_transcript_c0",
              "text" => "The first passage.",
              "filename" => "transcript.pdf",
              "chunk_index" => 0
            }
          ]
        )
        expect(result.dig("content", 0, "text")).to include("1 of 2 chunks", "Continue with cursor:")
        expect(events.first.payload).to include(
          tool_name: "get_document_chunks",
          input: { document_id: "abc123", limit: 1 }
        )
        expect(events.first.payload).not_to have_key(:results)
      end

      it "rejects a cursor issued for another document" do
        cursor = Base64.urlsafe_encode64(
          { version: 1, document_id: "another-document", offset: 1 }.to_json,
          padding: false
        )

        post_mcp(
          jsonrpc: "2.0",
          id: "9",
          method: "tools/call",
          params: {
            name: "get_document_chunks",
            arguments: { document_id: "abc123", cursor: cursor }
          }
        )

        result = response.parsed_body.fetch("result")
        expect(result["isError"]).to be true
        expect(result.dig("structuredContent", "error")).to include("Invalid cursor for document abc123")
      end
    end

    describe "search_passages" do
      it "instruments input and at most the first 10 passages" do
        passages = 11.times.map { |index| { rank: index + 1, text: "Passage #{index + 1}" } }
        allow(SemanticSearchMcp::PassageSearch).to receive(:search).and_return(
          text: "Found 11 passages",
          structured_content: { passages: passages }
        )

        events = capture_mcp_events do
          post_mcp(
            jsonrpc: "2.0",
            id: "instrument-passages",
            method: "tools/call",
            params: {
              name: "search_passages",
              arguments: { query: "Professor X", limit: 11 }
            }
          )
        end

        expect(events.length).to eq(1)
        expect(events.first.payload).to include(
          tool_name: "search_passages",
          input: { query: "Professor X", limit: 11 },
          results: passages.first(10),
          request_id: be_present
        )
      end

      it "returns vector-ranked passages with parent source metadata" do
        embedding = instance_double(GeminiEmbedding, embedding: [ [ 0.1, 0.2 ] ])
        allow(GeminiEmbedding).to receive(:new).and_return(embedding)
        passage_response = {
          "responseHeader" => { "status" => 0, "params" => {} },
          "response" => {
            "numFound" => 1,
            "start" => 0,
            "docs" => [
              {
                "id" => "abc123_transcript_c4",
                "chunk_text_tesi" => "A compelling story about Professor X.",
                "filename_ss" => "transcript.pdf",
                "chunk_index_i" => 4,
                "score" => 0.93
              }
            ]
          }
        }
        parent_response = {
          "responseHeader" => { "status" => 0, "params" => {} },
          "response" => {
            "numFound" => 1,
            "start" => 0,
            "docs" => [
              {
                "id" => "abc123",
                "title_display_tesi" => "Oral history with Professor X",
                "collection_title_ss" => "Oral History Collection"
              }
            ]
          }
        }
        allow(solr_connection).to receive(:send_and_receive).and_return(passage_response, parent_response)

        post_mcp(
          jsonrpc: "2.0",
          id: "10",
          method: "tools/call",
          params: {
            name: "search_passages",
            arguments: {
              query: "Professor X career milestones",
              document_ids: [ "abc123" ],
              limit: 5
            }
          }
        )

        result = response.parsed_body.fetch("result")
        expect(result["isError"]).not_to be true
        expect(result.dig("structuredContent", "search_type")).to eq("vector")
        expect(result.dig("structuredContent", "passages", 0)).to include(
          "rank" => 1,
          "text" => "A compelling story about Professor X.",
          "score" => 0.93,
          "chunk_index" => 4,
          "filename" => "transcript.pdf",
          "document_id" => "abc123",
          "document_title" => "Oral history with Professor X",
          "collection" => "Oral History Collection",
          "url" => "http://www.example.com/catalog/abc123"
        )
        expect(embedding).to have_received(:embedding).with(
          input: [ "Professor X career milestones" ],
          instruction: GeminiEmbedding::DEFAULT_QUERY_INSTRUCTION
        )
      end
    end
  end
end
