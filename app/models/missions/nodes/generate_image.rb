# frozen_string_literal: true

module Missions
  module Nodes
    # Node: Generate Image — calls an image generation model with a prompt.
    # Stores the generated image in Active Storage on the MissionRun.
    class GenerateImage
      include MissionNodePlugin
      include Missions::LlmNodeSupport

      FIELD_CONTRACT_ATTRIBUTES = [
        {
          key: "prompt",
          kind: :template,
          value_type: :string,
          description: "Image description prompt (supports {{variable}} interpolation)",
        },
        {
          key: "connector_id",
          kind: :id_ref,
          value_type: :string,
          description: "LLM connector ID",
          required: true,
        },
        {
          key: "model",
          kind: :id_ref,
          value_type: :string,
          description: "Image generation model identifier",
          required: true,
        },
        {
          key: "size",
          value_type: :string,
          description: "Image size (e.g. 1024x1024)",
        },
      ].freeze

      class << self
        def node_type = "generate_image"
        def node_label = "Generate Image"
        def node_icon = "fa-solid fa-image"
        def node_color = "#a855f7"
        def node_category = :llm
        def node_description = "Generates an image using an AI model"

        def field_contracts
          FIELD_CONTRACT_ATTRIBUTES.map { |attributes| field_contract(**attributes) }
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "image", type: :hash,
                description: "Image metadata: filename, url, blob_id, content_type, byte_size", },
              { name: "revised_prompt", type: :string,
                description: "Revised prompt returned by the model (if any)", },
            ],
          )
        end

        def default_output_ports
          [{ key: "default", label: "Image" }]
        end

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Generate Image (type: "generate_image")
            Generates an image using an AI image generation model.

            ### Configuration
            ```json
            { "connector_id": "1", "model": "gpt-image-1", "prompt": "A red panda", "size": "1024x1024" }
            ```
            - `connector_id` (required): ID of the LLM connector. Use `list_resources(kinds: ["llm_connectors", "default_models"])` for available connectors and the default image model.
            - `model` (required): Image model identifier (e.g. "gpt-image-1", "dall-e-3"). Use the default image model from `list_resources(kind: "default_models")` unless the user specifies a different one.
            - `prompt`: Image description prompt with {{variable}} interpolation.
            - `size`: Image dimensions (e.g. "1024x1024", "1792x1024"). Not all models support this.
            - Stores the generated image in Active Storage attached to the MissionRun.

            ### Output Ports
            - `default`: Image

            ### Output Variables
            - `image` (hash): File metadata with filename, blob_id, content_type, byte_size.
            - `revised_prompt` (string): Revised prompt returned by the model (if any).
          INSTRUCTIONS
        end
      end

      register_node!

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}

        runtime_config, _model, error = validate_connector_and_model(node_data, context:)
        return error if error

        prompt = resolve_prompt(context, node_data)
        return failure("Generate Image node has no prompt — nothing to generate") if prompt.blank?

        image = paint_image(runtime_config, node_data, context, prompt)
        file_meta = store_image(context, image, node_data)

        variables = { "image" => file_meta }
        variables["revised_prompt"] = image.revised_prompt if image.revised_prompt.present?

        NodeResult.new(status: :success, output: file_meta, variables:)
      rescue StandardError => e
        NodeResult.new(status: :failure, output: "Image generation error: #{e.message}")
      end

      private

      def resolve_prompt(context, node_data)
        prompt_template = node_data["prompt"] || ""
        prompt = context.interpolate(prompt_template)
        prompt.presence || resolve_user_input(context)
      end

      def paint_image(runtime_config, node_data, context, prompt)
        chat = build_llm_chat(runtime_config, node_data, context)
        chat.messages.create!(role: :user, content: prompt)

        paint_options = { model: runtime_config.model_id }
        paint_options[:size] = node_data["size"] if node_data["size"].present?

        image = chat.context.paint(prompt, **paint_options)
        chat.messages.create!(role: :assistant, content: "Image generated: #{image.revised_prompt || prompt}")
        image
      end

      def store_image(context, image, node_data)
        filename = generate_filename(node_data, image)
        content_type = image.mime_type || "image/png"
        blob_data = image.to_blob

        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(blob_data),
          filename:,
          content_type:,
        )

        run = context.mission_run
        run.files.attach(blob)

        {
          "filename" => blob.filename.to_s,
          "blob_id" => blob.id,
          "content_type" => blob.content_type,
          "byte_size" => blob.byte_size,
        }
      end

      def generate_filename(node_data, image)
        label = node_data["label"].presence || "generated_image"
        sanitized = label.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
        extension = (image.mime_type || "image/png").split("/").last
        "#{sanitized}_#{Time.current.to_i}.#{extension}"
      end
    end
  end
end
