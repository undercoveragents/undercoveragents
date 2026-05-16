# frozen_string_literal: true

module Missions
  module Nodes
    # I/O: Write File — Writes content to a file.
    # Accepts a content variable (or interpolated template) and a filename.
    # Outputs a file hash with download metadata attached to the MissionRun.
    class WriteFile
      include MissionNodePlugin

      class << self
        def node_type = "write_file"
        def node_label = "Write File"
        def node_icon = "fa-solid fa-file-export"
        def node_color = "#0891b2"
        def node_category = :node
        def node_description = "Writes content to a file"

        def field_contracts
          [
            field_contract(
              key: "filename",
              kind: :template,
              value_type: :string,
              description: "Output filename (supports {{variable}} interpolation)",
              required: true,
            ),
            field_contract(
              key: "content",
              kind: :template,
              value_type: :string,
              description: "File content (supports {{variable}} interpolation)",
              required: true,
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "file", type: :hash,
                description: "File metadata: filename, url, blob_id, content_type, byte_size", },
            ],
          )
        end

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Write File (type: "write_file")
            Writes content to a file on the MissionRun.

            ### Configuration
            ```json
            {
              "filename": "report_{{date}}.html",
              "content": "{{llm_node.response}}"
            }
            ```
            - `filename` (required): Output filename. Supports `{{variable}}` interpolation.
            - `content` (required): File content. Supports `{{variable}}` interpolation.

            ### Output Variables
            - `file`: Hash with `filename`, `url`, `blob_id`, `content_type`, `byte_size`.

            ### Output Ports
            - `default`: Output
          INSTRUCTIONS
        end
      end

      register_node!

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}

        filename = resolve_filename(context, node_data)
        return NodeResult.new(status: :failure, output: "Filename is required") if filename.blank?

        content = context.interpolate(node_data["content"].to_s)
        return NodeResult.new(status: :failure, output: "Content is required") if content.blank?

        file_meta = store_file(context, filename, content)

        NodeResult.new(
          status: :success,
          output: file_meta,
          variables: { "file" => file_meta },
        )
      end

      private

      def resolve_filename(context, node_data)
        raw = node_data["filename"].to_s
        return nil if raw.blank?

        context.interpolate(raw)
      end

      def store_file(context, filename, content)
        content_type = Marcel::MimeType.for(name: filename, extension: File.extname(filename))

        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(content),
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
    end
  end
end
