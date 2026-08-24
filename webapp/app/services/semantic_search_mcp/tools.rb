# frozen_string_literal: true

module SemanticSearchMcp
  # MCP tool metadata.
  module Tools
    INSTRUMENTATION_EVENT = "call.mcp_tool"
    LOGGED_RESULT_LIMIT = 10

    CATALOG_SEARCH = {
      name: "catalog_search_tool",
      description: "Search Stanford Libraries digital collections. Supports keyword, vector, and hybrid semantic search. " \
                   "Returns descriptive metadata, matched text chunks for semantic searches, and facet suggestions for refining results.",
      input_schema: -> { CatalogSearch.build_input_schema },
      output_schema: -> { CatalogSearch.build_output_schema },
      logged_result_key: :results
    }.freeze

    GET_DOCUMENT_CHUNKS = {
      name: "get_document_chunks",
      description: "Retrieve a catalog document's text chunks in stable order. Follow next_cursor until complete is true " \
                   "when the task requires scanning the entire document.",
      input_schema: -> { DocumentChunks.build_input_schema },
      output_schema: -> { DocumentChunks.build_output_schema },
      handler: ->(**arguments) { DocumentChunks.retrieve(**arguments) }
    }.freeze

    SEARCH_PASSAGES = {
      name: "search_passages",
      description: "Search text passages directly using vector similarity. Returns ranked passage text and parent-document " \
                   "source information. This is relevance-ranked and not an exhaustive document scan.",
      input_schema: -> { PassageSearch.build_input_schema },
      output_schema: -> { PassageSearch.build_output_schema },
      handler: ->(**arguments) { PassageSearch.search(**arguments) },
      logged_result_key: :passages
    }.freeze

    ALL = [ CATALOG_SEARCH, GET_DOCUMENT_CHUNKS, SEARCH_PASSAGES ].freeze
  end
end
