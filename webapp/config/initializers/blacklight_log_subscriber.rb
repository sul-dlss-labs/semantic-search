# frozen_string_literal: true

# Backport of Blacklight::LoggedParamsFilter (see the truncate-long-solr-log-values
# branch upstream). Delete this file, along with its spec, once we are on a
# Blacklight release that includes it; the released default needs no configuration.
#
# Blacklight 9.2.0 logs the full Solr parameters at debug level. Our KNN and
# vectorSimilarity queries carry an embedding serialized as a string of hundreds
# of floats, which buries the rest of the request. Replace any oversized value
# with a placeholder so the log line stays readable.
module TruncateSolrLogValues
  MAX_VALUE_LENGTH = 200

  def solr_request(event)
    payload = event.payload
    debug { "Solr fetch (#{event.duration.round(1)}ms): #{payload[:method]} #{payload[:path]} #{truncate_values(payload[:params].to_hash).inspect}" }
    debug { "Solr response: #{payload[:response].inspect}" } if verbose_logging?
  end

  private

  def truncate_values(value)
    case value
    when Hash then value.transform_values { |v| truncate_values(v) }
    when Array then value.map { |v| truncate_values(v) }
    when String then value.length > MAX_VALUE_LENGTH ? "OMITTED (#{value.length} characters)" : value
    else value
    end
  end
end

Blacklight::LogSubscriber.prepend(TruncateSolrLogValues)
