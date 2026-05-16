# frozen_string_literal: true

module MissionDesigner
  module ApplyFlowPatchEdgesGlobals
    private

    def apply_add_edges(state, add_edges)
      Array(add_edges).each do |raw_entry|
        entry = normalize_add_edge_entry(raw_entry)
        source = resolve_ref(state, entry["source"])
        target = resolve_ref(state, entry["target"])
        result = state.editor.add_edge(
          source_node_id: source,
          target_node_id: target,
          source_port: entry["source_port"],
        )
        if result[:error]
          state.errors << "add_edge(#{source}->#{target}): #{result[:error]}"
        else
          state.ops << { op: "add_edge", edge_id: result[:edge][:id], source:, target: }
        end
      end
    end

    def apply_remove_edges(state, remove_edges)
      Array(remove_edges).each do |raw_entry|
        entry = normalize_remove_edge_entry(raw_entry)
        result = state.editor.remove_edge(
          edge_id: entry["edge_id"],
          source_node_id: resolve_ref(state, entry["source"]),
          target_node_id: resolve_ref(state, entry["target"]),
        )
        if result[:error]
          state.errors << "remove_edge: #{result[:error]}"
        else
          state.ops << { op: "remove_edge", removed: result[:removed_edges].size }
        end
      end
    end

    def apply_add_globals(state, add_globals)
      Array(add_globals).each do |entry|
        result = state.editor.add_global_variable(
          key: entry["key"],
          value: entry["value"] || "",
          type: entry["type"] || "string",
        )
        if result[:error]
          state.errors << "add_global(#{entry["key"]}): #{result[:error]}"
        else
          state.ops << { op: "add_global", key: entry["key"] }
        end
      end
    end

    def apply_update_globals(state, update_globals)
      Array(update_globals).each do |entry|
        result = state.editor.update_global_variable(
          key: entry["key"],
          value: entry["value"],
          type: entry["type"],
        )
        if result[:error]
          state.errors << "update_global(#{entry["key"]}): #{result[:error]}"
        else
          state.ops << { op: "update_global", key: entry["key"] }
        end
      end
    end

    def apply_remove_globals(state, remove_globals)
      Array(remove_globals).each do |entry|
        key = entry.is_a?(Hash) ? entry["key"] : entry
        result = state.editor.remove_global_variable(key:)
        if result[:error]
          state.errors << "remove_global(#{key}): #{result[:error]}"
        else
          state.ops << { op: "remove_global", key: }
        end
      end
    end

    def normalize_add_edge_entry(raw_entry)
      entry = normalize_hash(raw_entry)
      edge = normalize_hash(entry["edge"])

      {
        "source" => first_present_from(
          entry,
          edge,
          primary_keys: ["source", "source_id", "source_node_id", "source_ref", "from"],
        ),
        "target" => first_present_from(
          entry,
          edge,
          primary_keys: ["target", "target_id", "target_node_id", "target_ref", "to"],
        ),
        "source_port" => first_present_from(
          entry,
          edge,
          primary_keys: ["source_port", "port", "source_handle", "handle"],
        ),
      }
    end

    def normalize_remove_edge_entry(raw_entry)
      return { "edge_id" => raw_entry } unless raw_entry.is_a?(Hash)

      entry = normalize_hash(raw_entry)
      edge = normalize_hash(entry["edge"])

      {
        "edge_id" => first_present_from(entry, edge, primary_keys: ["edge_id", "id"]),
        "source" => first_present_from(
          entry,
          edge,
          primary_keys: ["source", "source_id", "source_node_id", "source_ref", "from"],
        ),
        "target" => first_present_from(
          entry,
          edge,
          primary_keys: ["target", "target_id", "target_node_id", "target_ref", "to"],
        ),
      }
    end
  end
end
