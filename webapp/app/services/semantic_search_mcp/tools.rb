# frozen_string_literal: true

module SemanticSearchMcp
  # MCP tool metadata.
  module Tools
    CATALOG_SEARCH = {
      name: "catalog_search_tool",
      description: "Search Stanford Libraries digital collections. Supports keyword, vector, and hybrid semantic search. " \
                   "Returns descriptive metadata, matched text chunks for semantic searches, and facet suggestions for refining results.",
      input_schema: -> { CatalogSearch.build_input_schema }
    }.freeze

    GET_DOCUMENT_CHUNKS = {
      name: "get_document_chunks",
      description: "Retrieve a catalog document's text chunks in stable order. Follow next_cursor until complete is true " \
                   "when the task requires scanning the entire document.",
      input_schema: -> { DocumentChunks.build_input_schema },
      handler: ->(**arguments) { DocumentChunks.retrieve(**arguments) }
    }.freeze

    SEARCH_PASSAGES = {
      name: "search_passages",
      description: "Search text passages directly using vector similarity. Returns ranked passage text and parent-document " \
                   "source information. This is relevance-ranked and not an exhaustive document scan.",
      input_schema: -> { PassageSearch.build_input_schema },
      handler: ->(**arguments) { PassageSearch.search(**arguments) }
    }.freeze

    ALL = [ CATALOG_SEARCH, GET_DOCUMENT_CHUNKS, SEARCH_PASSAGES ].freeze
  end
end
