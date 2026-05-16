# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API V1 Swagger Docs", :unauthenticated do
  describe "GET /api/v1/swagger.json" do
    it "returns the OpenAPI spec" do
      get api_v1_swagger_path(format: :json)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["openapi"]).to eq("3.0.3")
      expect(json["paths"]).to have_key("/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations")
    end

    it "includes generic channel invocation schemas" do
      get api_v1_swagger_path(format: :json)

      json = response.parsed_body
      base_path = "/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations"
      expect(json["paths"]).to have_key(base_path)
      expect(json["paths"]).to have_key("#{base_path}/{id}")

      schema = json.dig("components", "schemas", "ChannelInvocationRequest", "properties")
      expect(schema["content"]["type"]).to eq("string")
      expect(schema["payload"]["type"]).to eq("object")
    end
  end
end
