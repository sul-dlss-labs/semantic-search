require 'googleauth'

class GoogleSearchService
  def self.neighbors(feature_vector, subjects: [])
    new(feature_vector, subjects:).neighbors
  end

  def initialize(feature_vector, subjects:)
    @feature_vector = feature_vector
    @subjects = subjects
  end

  attr_reader :feature_vector

  def deployed_index_id
    "open_access_deployed_1732727565391"
  end

  def queries
    [Google::Apis::AiplatformV1::GoogleCloudAiplatformV1FindNeighborsRequestQuery.new(
      approximate_neighbor_count: 10,
      datapoint: Google::Apis::AiplatformV1::GoogleCloudAiplatformV1IndexDatapoint.new(
        feature_vector:,
        restricts:
      ),
      per_crowding_attribute_neighbor_count: 1,
    )]
  end

  # A list of filters to apply to the query
  def restricts
    return [] unless @subjects.present?
    [
      Google::Apis::AiplatformV1::GoogleCloudAiplatformV1IndexDatapointRestriction.new(
                        namespace: "subject",
                        allow_list: @subjects
      )
    ]
  end

  def request_body
    Google::Apis::AiplatformV1::GoogleCloudAiplatformV1FindNeighborsRequest.new(
      deployed_index_id:,
      queries:,
      return_full_datapoint: true,
      num_neighbors: 100,
    )
  end

  def authorization
    scope = 'https://www.googleapis.com/auth/cloud-platform'
    Google::Auth.get_application_default([scope])
  end

  # @return [Array<Google::Apis::AiplatformV1::GoogleCloudAiplatformV1FindNeighborsResponseNeighbor>]
  def neighbors
    vertex_ai_service = Google::Apis::AiplatformV1::AiplatformService.new
    vertex_ai_service.root_url = "https://430778453.us-central1-768608702519.vdb.vertexai.goog/"
    vertex_ai_service.authorization = authorization

    # Project and location details
    project_id = "sul-ai-sandbox"
    location = "us-central1" # Change as appropriate

    index_endpoint_id = "5525191065109266432"
    endpoint = "projects/#{project_id}/locations/#{location}/indexEndpoints/#{index_endpoint_id}"

    begin
      response = vertex_ai_service.find_project_location_index_endpoint_neighbors(
        endpoint,
        request_body
      )
      response.nearest_neighbors.first.neighbors || []
    rescue Google::Apis::Error => e
      raise e
    end
  end
end
