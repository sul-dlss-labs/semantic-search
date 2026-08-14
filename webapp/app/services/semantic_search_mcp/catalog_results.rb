# frozen_string_literal: true

module SemanticSearchMcp
  # Formats catalog responses for MCP clients.
  module CatalogResults
    extend self

    def format(response:, query:, search_type:, filters:, config:, controller:)
      results = Array(response.documents).map { |document| format_document(document, controller) }
      facets = extract_facets(response, config)

      {
        text: result_text(response.total, query, filters, results, facets),
        structured_content: {
          query: query,
          search_type: search_type,
          filters: filters,
          total: response.total,
          results: results,
          facets: facets
        }
      }
    end

    private

    def format_document(document, controller)
      id = document.id || document["id"]
      {
        id: id,
        title: field_value(document, %w[title_display_tesi title_tesi title_tsim]) || "Untitled",
        authors: array_value(document, %w[author_person_ssim author_other_ssim]),
        format: field_value(document, %w[doc_type_ssi format_hsim]),
        created: field_value(document, [ "creation_date_dtsi" ]),
        collection: field_value(document, [ "collection_title_ss" ]),
        child_count: document["child_count_i"],
        url: record_url(controller, id)
      }.compact
    end

    def field_value(document, field_names)
      field_names.each do |field_name|
        value = document[field_name]
        return value.first if value.is_a?(Array) && value.any?
        return value if value.present?
      end
      nil
    end

    def array_value(document, field_names)
      field_names.flat_map { |field_name| Array(document[field_name]) }.compact_blank.presence
    end

    def record_url(controller, id)
      return controller.solr_document_url(id) if controller

      Rails.application.routes.url_helpers.solr_document_path(id)
    end

    def extract_facets(response, config)
      return {} unless response.respond_to?(:facet_fields)

      facet_keys = configured_facet_keys(config)
      response.facet_fields.each_with_object({}) do |(field_name, facet_data), facets|
        facet_config = config.facet_fields[field_name]
        next if facet_config&.label.blank?

        values = facet_values(facet_data)
        next if values.empty?

        key = facet_keys.fetch(field_name, clean_label(field_name))
        facets[key] = { label: facet_config.label, values: values }
      end
    rescue StandardError => e
      Rails.logger.warn "Could not process facets: #{e.message}"
      {}
    end

    def configured_facet_keys(config)
      used_keys = Set.new
      config.facet_fields.each_with_object({}) do |(field_name, facet_config), keys|
        next if facet_config.label.blank?

        label_key = clean_label(facet_config.label)
        key = used_keys.include?(label_key) ? clean_label(field_name) : label_key
        used_keys << key
        keys[field_name] = key
      end
    end

    def facet_values(facet_data)
      if facet_data.is_a?(Array)
        facet_data.each_slice(2).first(5).filter_map do |value, count|
          { value: value, count: count } if value && count
        end
      elsif facet_data.respond_to?(:items)
        facet_data.items.first(5).map { |item| { value: item.value, count: item.hits } }
      else
        []
      end
    end

    def clean_label(label)
      label.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
    end

    def result_text(total, query, filters, results, facets)
      applied_filters = filter_text(filters)
      return "No results found for query: #{query}#{applied_filters}" if results.empty?

      "Found #{total} results#{applied_filters} (showing #{results.length}):\n\n" \
        "#{formatted_results(results)}#{facet_text(facets)}"
    end

    def filter_text(filters)
      return "" if filters.blank?

      applied = filters.map { |key, value| "#{key}: #{value}" }.join(", ")
      " with filters (#{applied})"
    end

    def formatted_results(results)
      results.map.with_index(1) do |result, index|
        lines = [ "#{index}. #{result[:title]}" ]
        lines << "   Authors: #{result[:authors].join(', ')}" if result[:authors]&.any?
        lines << "   Format: #{result[:format]}" if result[:format]
        lines << "   Created: #{result[:created]}" if result[:created]
        lines << "   Collection: #{result[:collection]}" if result[:collection]
        lines << "   Child count: #{result[:child_count]}" if result[:child_count]
        lines << "   URL: #{result[:url]}"
        lines.join("\n")
      end.join("\n\n")
    end

    def facet_text(facets)
      return "" if facets.empty?

      options = facets.map do |_key, facet|
        values = facet[:values].map { |value| "#{value[:value]} (#{value[:count]})" }.join(", ")
        "- #{facet[:label]}: #{values}"
      end
      "\n\nAvailable refinement options:\n#{options.join("\n")}"
    end
  end
end
