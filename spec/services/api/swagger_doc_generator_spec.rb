# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::SwaggerDocGenerator do
  subject(:result) { described_class.new.call }

  describe "#call" do
    it "returns a valid OpenAPI 3.0 structure" do
      expect(result[:openapi]).to eq("3.0.3")
      expect(result[:info][:title]).to include("API")
      expect(result[:info][:version]).to eq("1.0")
      expect(result[:components][:securitySchemes][:bearerAuth][:type]).to eq("http")
    end

    it "documents the channel invocation create and show paths", :aggregate_failures do
      expect(result[:paths]).to have_key("/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations")
      expect(result[:paths]).to have_key("/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations/{id}")

      create_path = result[:paths]["/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations"][:post]
      show_path = result[:paths]["/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations/{id}"][:get]

      expect(create_path[:tags]).to eq(["Channel Invocations"])
      expect(show_path[:tags]).to eq(["Channel Invocations"])
    end

    it "describes the shared path parameters", :aggregate_failures do
      params = result[:paths]["/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations"][:post][:parameters]

      expect(params).to include(
        hash_including(name: "channel_slug", in: "path", required: true),
        hash_including(name: "target_slug", in: "path", required: true),
      )
    end

    it "documents the generic channel invocation request schema", :aggregate_failures do
      schema = result[:components][:schemas][:ChannelInvocationRequest]

      expect(schema[:properties]).to include(
        content: hash_including(type: "string"),
        payload: hash_including(type: "object"),
        callback_url: hash_including(type: "string", format: "uri"),
        response_mode: hash_including(enum: ["async", "sync"]),
      )
    end

    it "documents the generic invocation response schema", :aggregate_failures do
      schema = result[:components][:schemas][:InvocationResponse]

      expect(schema[:properties]).to include(
        invocation_id: hash_including(type: "integer"),
        invocation_type: hash_including(enum: ["mission_run", "chat"]),
        channel: hash_including(type: "object"),
        target: hash_including(type: "object"),
      )
      expect(schema[:properties][:result][:properties]).to include(
        content: hash_including(type: "string", nullable: true),
        output: hash_including(type: "object", nullable: true),
      )
    end
  end
end
