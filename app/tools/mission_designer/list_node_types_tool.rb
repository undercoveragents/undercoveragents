# frozen_string_literal: true

module MissionDesigner
  # Lists all available mission node types with brief metadata.
  # Use get_node_type_info for detailed configuration instructions.
  class ListNodeTypesTool < RubyLLM::Tool
    description "Lists all available node types (key, label, ports). " \
                "Use only when the needed node type is unclear; for straightforward builds, start editing."

    def name
      "list_node_types"
    end

    def execute
      types = MissionNodePlugin.all_types
      grouped = types.group_by { |t| t[:category] }

      parts = ["## Available Node Types\n"]

      grouped.each do |category, nodes|
        parts << "### #{category.to_s.titleize}"
        nodes.each do |node|
          ports = node.fetch(:output_ports, [{ key: "default", label: "Output" }])
          port_str = ports.map { |p| p[:key] }.join(", ")
          singleton_str = node[:singleton] ? " [singleton]" : ""
          parts << "- `#{node[:key]}` (#{node[:label]}): #{node[:description]} — ports: #{port_str}#{singleton_str}"
        end
        parts << ""
      end

      parts.join("\n")
    rescue StandardError => e
      "Error listing node types: #{e.message}"
    end
  end
end
