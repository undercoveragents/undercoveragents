# frozen_string_literal: true

module MissionDesigner
  # Adds or removes edges (connections) between nodes.
  class ManageEdgesTool < BaseTool
    SOURCE_PORT_DESCRIPTION = "The output port on the source node. Required for multi-port sources. " \
                              "Examples: 'true'/'false' for condition, 'loop'/'done' for iterator/loop, " \
                              "'success'/'error' for http_request, 'match'/'no_match' for filter"

    description "Adds or removes an edge between two nodes. " \
                "Specify source_port whenever the source node has multiple outputs."

    param :action, desc: "Action to perform: 'add' to create a connection, 'remove' to delete one"
    param :source_node_id, desc: "The ID of the source (upstream) node"
    param :target_node_id, desc: "The ID of the target (downstream) node"
    param :source_port, desc: SOURCE_PORT_DESCRIPTION, required: false
    param :edge_id, desc: "The ID of a specific edge to remove (alternative to source/target pair)",
                    required: false

    def initialize(mission, runtime_context: nil)
      super
    end

    def name
      "manage_edges"
    end

    def execute(action:, source_node_id:, target_node_id:, source_port: nil, edge_id: nil)
      authorize_mission_update!(mission)
      editor = Missions::FlowEditor.new(mission)

      case action
      when "add"
        add_edge(editor, source_node_id, target_node_id, source_port)
      when "remove"
        remove_edge(editor, source_node_id, target_node_id, edge_id)
      else
        "Unknown action: '#{action}'. Use 'add' or 'remove'."
      end
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing edge: #{e.message}"
    end

    private

    def add_edge(editor, source, target, port)
      result = editor.add_edge(source_node_id: source, target_node_id: target, source_port: port)

      if result[:error]
        "Error: #{result[:error]}"
      else
        edge = result[:edge]
        "Edge added: `#{edge[:source]}` (port: #{edge[:source_port]}) → `#{edge[:target]}` (id: `#{edge[:id]}`)"
      end
    end

    def remove_edge(editor, source, target, edge_id)
      result = if edge_id.present?
                 editor.remove_edge(edge_id:)
               else
                 editor.remove_edge(source_node_id: source, target_node_id: target)
               end

      if result[:error]
        "Error: #{result[:error]}"
      else
        count = result[:removed_edges].size
        "#{count} edge(s) removed."
      end
    end
  end
end
