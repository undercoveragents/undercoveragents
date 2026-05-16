# frozen_string_literal: true

module MissionDesigner
  # Removes a node and all its connected edges from the mission flow.
  class RemoveNodeTool < BaseTool
    description "Removes a node and all edges connected to it."

    param :node_id, desc: "The ID of the node to remove (e.g. 'node-abc123')"

    def initialize(mission, runtime_context: nil)
      super
    end

    def name
      "remove_node"
    end

    def execute(node_id:)
      authorize_mission_update!(mission)
      editor = Missions::FlowEditor.new(mission)
      result = editor.remove_node(node_id:)

      if result[:error]
        "Error: #{result[:error]}"
      else
        format_removal(result)
      end
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error removing node: #{e.message}"
    end

    private

    def format_removal(result)
      node = result[:removed_node]
      "Node `#{node[:id]}` (#{node[:name]}, type: #{node[:type]}) removed. " \
        "#{result[:removed_edges_count]} connected edge(s) also removed."
    end
  end
end
