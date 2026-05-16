# frozen_string_literal: true

module Api
  class SwaggerDocGenerator
    def call
      {
        openapi: "3.0.3",
        info:,
        servers: [{ url: "/" }],
        security: [{ bearerAuth: [] }],
        paths: build_paths,
        components:,
      }
    end

    private

    def info
      {
        title: "#{APP_NAME} API",
        version: "1.0",
        description: "API for invoking published channel targets and retrieving invocation results. " \
                     "Authenticate with a channel Bearer token obtained from the Channels admin surface.",
      }
    end

    def components
      {
        securitySchemes: {
          bearerAuth: {
            type: "http",
            scheme: "bearer",
            description: "Channel token generated in the admin Channels surface",
          },
        },
        schemas: build_schemas,
      }
    end

    def build_paths
      {
        invocation_collection_path => { post: create_invocation_operation },
        invocation_member_path => { get: show_invocation_operation },
      }
    end

    def invocation_collection_path
      "/api/v1/channels/{channel_slug}/targets/{target_slug}/invocations"
    end

    def invocation_member_path
      "#{invocation_collection_path}/{id}"
    end

    def create_invocation_operation
      {
        tags: ["Channel Invocations"],
        summary: "Invoke a published channel target",
        operationId: "createChannelInvocation",
        parameters: shared_parameters,
        requestBody: invocation_request_body,
        responses: create_invocation_responses,
      }
    end

    def show_invocation_operation
      {
        tags: ["Channel Invocations"],
        summary: "Read a previously created channel invocation",
        operationId: "showChannelInvocation",
        parameters: shared_parameters + [invocation_id_parameter],
        responses: show_invocation_responses,
      }
    end

    def invocation_request_body
      {
        required: false,
        content: json_content("#/components/schemas/ChannelInvocationRequest"),
      }
    end

    def create_invocation_responses
      {
        "200" => json_response("Synchronous agent invocation response"),
        "202" => json_response("Accepted async mission or agent invocation"),
        "401" => { description: "Unauthorized — invalid or missing token" },
        "404" => { description: "Channel or target not found" },
        "422" => { description: "Invalid invocation payload" },
      }
    end

    def show_invocation_responses
      {
        "200" => json_response("Invocation result"),
        "401" => { description: "Unauthorized — invalid or missing token" },
        "404" => { description: "Invocation not found" },
      }
    end

    def json_response(description)
      {
        description:,
        content: json_content("#/components/schemas/InvocationResponse"),
      }
    end

    def json_content(schema_ref)
      { "application/json" => { schema: { "$ref" => schema_ref } } }
    end

    def build_schemas
      {
        ChannelInvocationRequest: channel_invocation_request_schema,
        InvocationResponse: invocation_response_schema,
      }
    end

    def shared_parameters
      [channel_slug_parameter, target_slug_parameter]
    end

    def channel_slug_parameter
      {
        name: "channel_slug",
        in: "path",
        required: true,
        schema: { type: "string" },
        description: "Slug of the published channel.",
      }
    end

    def target_slug_parameter
      {
        name: "target_slug",
        in: "path",
        required: true,
        schema: { type: "string" },
        description: "Slug of the published channel target.",
      }
    end

    def invocation_id_parameter
      {
        name: "id",
        in: "path",
        required: true,
        schema: { type: "integer" },
        description: "Invocation identifier returned by the create call.",
      }
    end

    def channel_invocation_request_schema
      {
        type: "object",
        properties: channel_invocation_request_properties,
      }
    end

    def channel_invocation_request_properties
      {
        content: string_property("Prompt content for agent targets."),
        payload: object_property("Structured input payload for mission targets."),
        callback_url: string_property("Optional webhook URL for async mission completions.", format: "uri"),
        response_mode: string_property(
          "Optional override for agent-target response mode when the channel supports it.",
          enum: ["async", "sync"],
        ),
      }
    end

    def invocation_response_schema
      {
        type: "object",
        properties: invocation_response_properties,
      }
    end

    def invocation_response_properties
      {
        invocation_id: { type: "integer" },
        invocation_type: { type: "string", enum: ["mission_run", "chat"] },
        status: { type: "string" },
        channel: object_schema({ slug: { type: "string" }, name: { type: "string" } }),
        target: object_schema({ slug: { type: "string" }, name: { type: "string" }, kind: { type: "string" } }),
        title: string_property,
        messages: messages_schema,
        started_at: string_property(format: "date-time"),
        completed_at: string_property(format: "date-time"),
        duration: { type: "number", nullable: true },
        result: result_schema,
        error: string_property,
      }
    end

    def messages_schema
      {
        type: "array",
        nullable: true,
        items: object_schema(message_properties),
      }
    end

    def message_properties
      {
        id: { type: "integer" },
        role: { type: "string" },
        content: { type: "string" },
        created_at: { type: "string", format: "date-time" },
      }
    end

    def result_schema
      object_schema(
        {
          content: string_property,
          output: object_property,
          meta: object_property,
        },
        nullable: true,
      )
    end

    def object_schema(properties, nullable: false)
      { type: "object", properties:, nullable: }.compact
    end

    def string_property(description = nil, format: nil, enum: nil)
      { type: "string", nullable: true, description:, format:, enum: }.compact
    end

    def object_property(description = nil)
      { type: "object", nullable: true, additionalProperties: true, description: }.compact
    end
  end
end
