require 'googleauth'

class GoogleSearchService
  def self.neighbors(feature_vector)
    new(feature_vector).neighbors
  end

  def initialize(feature_vector)
    @feature_vector = feature_vector
  end

  attr_reader :feature_vector

  def deployed_index_id
    "open_access_deploy_1730924393870"
  end

  def queries
    [Google::Apis::AiplatformV1::GoogleCloudAiplatformV1FindNeighborsRequestQuery.new(
      approximate_neighbor_count: 10,
      datapoint: Google::Apis::AiplatformV1::GoogleCloudAiplatformV1IndexDatapoint.new(
        feature_vector:
      )
    )]
  end

  def request_body
    Google::Apis::AiplatformV1::GoogleCloudAiplatformV1FindNeighborsRequest.new(
      deployed_index_id:,
      queries:,
      return_full_datapoint: false
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
      response.nearest_neighbors.first.neighbors
    rescue Google::Apis::Error => e
      puts "Error occurred: #{e.message}"
    end
  end
end
