# frozen_string_literal: true

module MissionDesigner
  module ApplyFlowPatchNodes
    private

    def apply_add_nodes(state, add_nodes)
      Array(add_nodes).each { |entry| apply_add_node_entry(state, entry) }
    end

    def apply_add_node_entry(state, raw_entry)
      entry = normalize_add_node_entry(raw_entry)
      temp_id = entry["temp_id"]
      normalized_config = normalize_tool_config(state, node_type: entry["type"], config: entry["config"])
      result = add_node_for_entry(state, entry, normalized_config)

      return record_added_node_error(state, temp_id, entry, result) if result[:error]

      record_added_node_success(state, temp_id, entry, result, normalized_config)
    end

    def add_node_for_entry(state, entry, normalized_config)
      state.editor.add_node(
        type: entry["type"],
        name: entry["name"],
        config: normalized_config,
        near_node_id: resolve_ref(state, entry["near_node_id"]),
      )
    end

    def record_added_node_error(state, temp_id, entry, result)
      state.errors << "add_node(#{temp_id || entry["type"]}): #{result[:error]}"
    end

    def record_added_node_success(state, temp_id, entry, result, normalized_config)
      remember_temp_node(state, temp_id, result[:node])
      state.added_node_entries << build_added_node_entry(entry, result[:node][:id], normalized_config)
      state.ops << { op: "add_node", temp_id:, node_id: result[:node][:id], type: entry["type"] }
    end

    def remember_temp_node(state, temp_id, node)
      return if temp_id.blank?

      state.temp_ids[temp_id] = node[:id]
      return if node[:variable_name].blank?

      state.temp_variables[temp_id] = node[:variable_name]
    end

    def build_added_node_entry(entry, node_id, normalized_config)
      {
        node_id:,
        node_type: entry["type"],
        raw_config: normalize_config_hash(entry["config"]),
        applied_config: normalized_config,
      }
    end

    def apply_update_nodes(state, update_nodes)
      Array(update_nodes).each do |raw_entry|
        entry = normalize_update_node_entry(raw_entry)
        node_id = resolve_ref(state, entry["id"])
        if node_id.blank?
          state.errors << "update_node: missing `id`"
          next
        end

        record_update_node_result(state, node_id, entry)
      end
    end

    def record_update_node_result(state, node_id, entry)
      result = state.editor.update_node(
        node_id:,
        data: normalized_update_node_config(state, node_id, entry["config"]),
      )
      if result[:error]
        state.errors << "update_node(#{node_id}): #{result[:error]}"
      else
        state.ops << { op: "update_node", node_id: }
      end
    end

    def apply_remove_nodes(state, remove_nodes)
      Array(remove_nodes).each do |entry|
        node_id = resolve_ref(state, normalized_remove_node_id(entry))
        result = state.editor.remove_node(node_id:)
        if result[:error]
          state.errors << "remove_node(#{node_id}): #{result[:error]}"
        else
          state.ops << { op: "remove_node", node_id: }
        end
      end
    end

    def normalize_add_node_entry(raw_entry)
      entry = normalize_hash(raw_entry)
      node = normalize_hash(entry["node"])

      {
        "temp_id" => first_present_from(entry, node, primary_keys: ["temp_id", "ref"]),
        "type" => first_present_from(entry, node, primary_keys: ["type", "node_type"]),
        "name" => first_present_from(entry, node, primary_keys: ["name", "label"]),
        "config" => normalize_config_hash(entry["config"] || node["config"]),
        "near_node_id" => first_present_from(
          entry,
          node,
          primary_keys: ["near_node_id", "near_node_ref", "near_node", "near"],
        ),
      }
    end

    def normalize_update_node_entry(raw_entry)
      entry = normalize_hash(raw_entry)
      node = normalize_hash(entry["node"])
      config = normalize_config_hash(entry["config"] || node["config"])
      label = first_present_from(entry, node, primary_keys: ["name", "label"])
      config["label"] = label if label.present?

      {
        "id" => first_present_from(entry, node, primary_keys: ["id", "node_id", "node_ref", "ref"]),
        "config" => config,
      }
    end

    def normalized_remove_node_id(entry)
      return entry unless entry.is_a?(Hash)

      normalized = normalize_hash(entry)
      node = normalize_hash(normalized["node"])

      first_present_from(normalized, node, primary_keys: ["id", "node_id", "node_ref", "ref"])
    end
  end
end
