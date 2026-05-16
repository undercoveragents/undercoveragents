# frozen_string_literal: true

module MissionDesigner
  # Updates an existing node's configuration.
  class UpdateNodeTool < BaseTool
    description "Partial update of a node's config (provided fields are merged, others preserved)."

    param :id, desc: "The ID of the node to update (e.g. 'node-abc123')"
    param :config, desc: "JSON string with fields to update (e.g. '{\"prompt\": \"new prompt\", \"temperature\": 0.5}')"
    param :name, desc: "New display name for the node", required: false

    def initialize(mission, runtime_context: nil)
      super
    end

    def name
      "update_node"
    end

    def execute(id:, config: nil, name: nil)
      authorize_mission_update!(mission)
      data = build_update_data(name, config)
      return data if data.is_a?(String)

      return "No changes specified. Provide config and/or name." if data.empty?

      perform_update(id:, data:)
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error updating node: #{e.message}"
    end

    private

    def build_update_data(name, config)
      data = {}
      data["label"] = name if name.present?
      return data if config.blank?

      parsed = parse_config(config)
      parsed.is_a?(String) ? parsed : data.merge(parsed)
    end

    def perform_update(id:, data:)
      editor = Missions::FlowEditor.new(mission)
      result = editor.update_node(node_id: id, data:)
      return "Error: #{result[:error]}" if result[:error]

      format_update_result(result[:node])
    end

    def format_update_result(node)
      msg = "Node `#{node[:id]}` updated successfully (#{node[:name]}, type: #{node[:type]})."
      msg += " Variable prefix: `#{node[:variable_name]}`." if node[:variable_name].present?
      msg
    end

    def parse_config(config)
      return config if config.is_a?(Hash) # LLM may send an object instead of a JSON string

      JSON.parse(config)
    rescue JSON::ParserError => e
      "Invalid config JSON: #{e.message}. Provide a valid JSON string."
    end
  end
end
