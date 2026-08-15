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
  end
end
