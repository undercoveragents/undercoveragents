# frozen_string_literal: true

module MissionDesigner
  # Atomic batch editor for a mission flow. The model sends one JSON patch and
  # the tool runs the whole diff in order, then validates and summarizes it.
  class ApplyFlowPatchTool < BaseTool
    include ApplyFlowPatchEdgesGlobals
    include ApplyFlowPatchNodes
    include ApplyFlowPatchNormalization
    include ApplyFlowPatchResult

    description "Apply a batch patch to the mission flow in a single call. " \
                "Pass a JSON string with keys: add_nodes, update_nodes, remove_nodes, " \
                "add_edges, remove_edges, add_globals, update_globals, remove_globals. " \
                "For update_nodes, use read_flow-style id/name/config entries. " \
                "Use temp_id on new nodes only for same-patch node/edge references. " \
                "The tool rewrites same-patch temp_id variable references to the real var_prefix when possible and " \
                "normalizes common set_variable aliases like variables[] into assignments. " \
                "For add_edges, source_port is required whenever the source node has multiple outputs. " \
                "Pass mission_id to target a mission created earlier in the same turn. " \
                "The tool auto-arranges and validates the flow."

    param :patch, desc: "JSON patch string. Example: " \
                        '{"add_nodes":[{"temp_id":"n1","type":"input"},' \
                        '{"temp_id":"n2","type":"llm","config":{...}}],' \
                        '"add_edges":[{"source":"n1","target":"n2"}]}'

    param :mission_id,
          desc: "Optional mission ID or slug to patch. Use this after creating a mission in the same turn.",
          required: false

    PatchState = Struct.new(
      :mission,
      :editor,
      :temp_ids,
      :temp_variables,
      :added_node_entries,
      :rewritten_temp_ids,
      :ops,
      :errors,
      keyword_init: true,
    )
    private_constant :PatchState

    def name
      "apply_flow_patch"
    end

    def execute(patch:, mission_id: nil)
      parsed = parse_patch(patch)
      return parsed if parsed.is_a?(String)

      mission = resolve_target_mission(mission_id)
      authorize_mission_update!(mission)
      state = build_state(mission)

      apply_patch(state, parsed)
      broadcast_arrange(state.mission) unless state.ops.empty?
      format_result(state)
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error applying patch: #{e.message}"
    end

    private

    def parse_patch(raw)
      return "Patch must not be blank." if raw.blank?

      data = JSON.parse(raw)
      return "Patch must be a JSON object." unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      "Invalid JSON patch: #{e.message}"
    end

    def build_state(mission)
      PatchState.new(
        mission:,
        editor: Missions::FlowEditor.new(mission),
        temp_ids: {},
        temp_variables: {},
        added_node_entries: [],
        rewritten_temp_ids: [],
        ops: [],
        errors: [],
      )
    end

    def apply_patch(state, patch)
      apply_add_nodes(state, patch["add_nodes"])
      reconcile_added_node_configs(state)
      apply_update_nodes(state, patch["update_nodes"])
      apply_remove_nodes(state, patch["remove_nodes"])
      apply_add_edges(state, patch["add_edges"])
      apply_remove_edges(state, patch["remove_edges"])
      apply_add_globals(state, patch["add_globals"])
      apply_update_globals(state, patch["update_globals"])
      apply_remove_globals(state, patch["remove_globals"])
    end
  end
end
