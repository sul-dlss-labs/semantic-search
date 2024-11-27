require 'googleauth'

class GoogleEmbeddingService
  def self.embedding_for(text)
    new(text).fetch_embedding
  end

  def initialize(text)
    @text = text
  end

  def request_body
    Google::Apis::AiplatformV1::GoogleCloudAiplatformV1PredictRequest.new(instances: [ { content: @text } ],
      parameters: {})
  end

  def authorization
    scope = 'https://www.googleapis.com/auth/cloud-platform'
    Google::Auth.get_application_default([scope])
  end

  # @return [Array] a 768 dimension vector
  def fetch_embedding
    vertex_ai_service = Google::Apis::AiplatformV1::AiplatformService.new
    vertex_ai_service.root_url = "https://us-central1-aiplatform.googleapis.com/"
    vertex_ai_service.authorization = authorization

    # Project and location details
    project_id = "sul-ai-sandbox"
    location = "us-central1" # Change as appropriate

    # Resource name for the model
    model_id = "text-embedding-005"
    endpoint = "projects/#{project_id}/locations/#{location}/publishers/google/models/#{model_id}"

    begin
      response = vertex_ai_service.predict_project_location_publisher_model(
        endpoint,
        request_body
      )
      response.predictions.first['embeddings']['values']
    rescue Google::Apis::Error => e
      puts "Error occurred: #{e.message}"
    end
  end
end
