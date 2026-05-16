# frozen_string_literal: true

module MissionDesigner
  # Adds a new node to the mission flow.
  class AddNodeTool < BaseTool
    description "Adds a node to the mission flow. Returns the new node ID. " \
                "Use get_node_type_info first to learn the required config."

    param :node_type, desc: "The node type key (e.g. 'llm', 'condition', 'iterator')"
    param :name, desc: "Display name for the node", required: false
    param :config, desc: "JSON string with node configuration " \
                         "(e.g. '{\"prompt\": \"...\", \"connector_id\": \"1\"}')",
                   required: false
    param :near_node_id, desc: "ID of an existing node to place this new node near (e.g. 'node-abc123'). " \
                               "The new node will be positioned close to this node so auto-arrange " \
                               "doesn't move it too far. Use the upstream node's ID.",
                         required: false

    def initialize(mission, runtime_context: nil)
      super
    end

    def name
      "add_node"
    end

    def execute(node_type:, name: nil, config: nil, near_node_id: nil)
      authorize_mission_update!(mission)
      parsed_config = parse_config(config)
      return parsed_config if parsed_config.is_a?(String) # error message

      editor = Missions::FlowEditor.new(mission)
      result = editor.add_node(
        type: node_type, name:, config: parsed_config,
        near_node_id:,
      )

      if result[:error]
        "Error: #{result[:error]}"
      else
        format_success(result[:node], node_type, editor)
      end
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error adding node: #{e.message}"
    end

    private

    def parse_config(config)
      return {} if config.blank?
      return config if config.is_a?(Hash) # LLM may send an object instead of a JSON string

      JSON.parse(config)
    rescue JSON::ParserError => e
      "Invalid config JSON: #{e.message}. Provide a valid JSON string."
    end

    def format_success(node, node_type, editor)
      parts = base_success_parts(node)
      parts << "- Available ports: #{format_ports(node_type)}" if multi_port_type?(node_type)
      parts << append_validation_hint(editor)
      parts << "Use this ID to connect it to other nodes with the manage_edges tool."
      parts.compact.join("\n")
    end

    def base_success_parts(node)
      pos = node[:position] || {}
      [
        "Node added successfully.",
        "- ID: `#{node[:id]}`",
        "- Type: #{node[:type]}",
        "- Name: #{node[:name]}",
        "- Position: (#{pos["x"].to_i}, #{pos["y"].to_i})",
        "- Variable prefix: `#{node[:variable_name]}` " \
        "(use `{{#{node[:variable_name]}.variable}}` to reference outputs)",
      ]
    end

    def multi_port_type?(type)
      ["condition", "switch", "iterator", "loop", "filter", "http_request"].include?(type)
    end

    def format_ports(type)
      klass = MissionNodePlugin.resolve(type)
      return "" unless klass

      klass.default_output_ports.map { |p| "`#{p[:key]}`" }.join(", ")
    end

    def append_validation_hint(_editor)
      result = Missions::FlowValidator.call(@mission)
      return nil if result.valid? && result.warnings.empty?

      count = result.config_errors.values.flatten.size + result.structural_issues.size
      return nil if count.zero?

      "⚠ #{count} validation issue(s) in flow. Use `validate_flow` for details."
    end
  end
end
