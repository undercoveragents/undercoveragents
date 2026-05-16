# frozen_string_literal: true

module MissionDesigner
  # Returns field schema, output ports, and output variables for a specific node type.
  # For shared resource IDs (LLM connectors, tools, agents, missions, default models)
  # the agent should call `list_resources` with the appropriate `kind` or `kinds`.
  class NodeTypeInfoTool < RubyLLM::Tool
    description "Returns config schema, ports, and output vars for one or more node types. " \
                "Use only when the config shape is genuinely unclear. " \
                "It does not tell you live variable names; use list_node_variables for unknown variable errors. " \
                "For resource IDs use list_resources."

    param :node_type, desc: "A node type key (e.g. 'llm', 'condition', 'iterator'). " \
                            "Use list_node_types to see available type keys.", required: false

    param :node_types,
          desc: "Optional array of node type keys when you need multiple schemas in one call.",
          type: :array,
          required: false

    HINTS = {
      "llm" => "Resource IDs: call list_resources(kinds: ['llm_connectors', 'default_models', 'tools']).",
      "generate_image" => "Resource IDs: call list_resources(kinds: ['llm_connectors', 'default_models']).",
      "agent" => "Resource IDs: call list_resources(kinds: ['agents']).",
      "mission" => "Resource IDs: call list_resources(kinds: ['missions']).",
    }.freeze

    def name
      "get_node_type_info"
    end

    def execute(node_type: nil, node_types: nil)
      requested_types = normalize_requested_types(node_type:, node_types:)
      return "Provide node_type or node_types. Use list_node_types to see available types." if requested_types.empty?

      return render_node_type(requested_types.first) if requested_types.one?

      requested_types.map { |requested_type| render_node_type(requested_type) }.join("\n\n")
    rescue StandardError => e
      "Error getting node type info: #{e.message}"
    end

    private

    def normalize_requested_types(node_type:, node_types:)
      [node_type, node_types]
        .flatten
        .compact
        .flat_map { |value| value.to_s.split(",") }
        .map(&:strip)
        .compact_blank
        .uniq
    end

    def render_node_type(node_type)
      klass = MissionNodePlugin.resolve(node_type)
      return "Unknown node type: '#{node_type}'. Use list_node_types to see available types." unless klass

      parts = [klass.designer_instructions]
      hint = HINTS[node_type]
      parts << "### Related Resource Lookups\n#{hint}" if hint
      parts.compact.join("\n\n")
    end
  end
end
