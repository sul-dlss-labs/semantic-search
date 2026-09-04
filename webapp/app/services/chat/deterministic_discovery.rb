# frozen_string_literal: true

module Chat
  # Pairs broad discovery with a passage search scoped to the best catalog candidates.
  class DeterministicDiscovery
    TOOL_NAMES = %w[catalog_search_tool search_passages].freeze
    SECOND_STAGE_DOCUMENT_LIMIT = 5

    def self.handles?(name)
      TOOL_NAMES.include?(name)
    end

    def initialize(tool_runner:)
      @tool_runner = tool_runner
    end

    def call(query:, requested_name:, requested_arguments:)
      passage_search = [ "search_passages", { "query" => query } ]
      catalog_search = [ "catalog_search_tool", { "query" => query, "search_type" => "vector", "rows" => 10 } ]
      passage_result = run(passage_search)
      catalog_result = run(catalog_search)
      results = [ [ passage_search.first, passage_result ], [ catalog_search.first, catalog_result ] ]

      document_ids = second_stage_document_ids(catalog_result)
      if document_ids.any?
        constrained_search = [ "search_passages", { "query" => query, "document_ids" => document_ids } ]
        # Constrained passages are the most focused evidence. Put them first so the compactor's
        # per-type cap cannot discard them behind the broader global passage results.
        results.unshift([ constrained_search.first, run(constrained_search) ])
      end

      requested_search = [ requested_name, requested_arguments ]
      results << [ requested_name, run(requested_search) ] unless [ passage_search, catalog_search ].include?(requested_search)

      combine(results)
    end

    private

    def run(search)
      name, arguments = search
      @tool_runner.call(name:, arguments:)
    end

    def second_stage_document_ids(result)
      return [] if result.blank? || result[:error]

      content = result[:structured_content].to_h.deep_symbolize_keys
      Array(content[:results]).filter_map { |candidate| candidate.to_h.deep_symbolize_keys[:id].presence }
        .uniq
        .first(SECOND_STAGE_DOCUMENT_LIMIT)
    end

    def combine(searches)
      successful = searches.reject { |_name, result| result[:error] }
      structured_content = successful.each_with_object({ passages: [], results: [] }) do |(_name, result), content|
        result_content = result[:structured_content].to_h.deep_symbolize_keys
        content[:passages].concat(Array(result_content[:passages]))
        content[:results].concat(Array(result_content[:results]))
      end
      text = searches.map do |name, result|
        "#{name}:\n#{result[:text]}"
      end.join("\n\n")

      { text:, structured_content:, error: successful.empty? }
    end
  end
end
