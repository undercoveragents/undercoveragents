# frozen_string_literal: true

module MissionDesigner
  module ApplyFlowPatchNormalization
    private

    def normalize_hash(raw_entry)
      raw_entry.is_a?(Hash) ? raw_entry.deep_stringify_keys : {}
    end

    def normalize_config_hash(raw_entry)
      raw_entry.is_a?(Hash) ? raw_entry.deep_stringify_keys : {}
    end

    def normalized_update_node_config(state, node_id, config)
      normalize_tool_config(state, node_type: current_node_type(state.mission, node_id), config:)
    end

    def reconcile_added_node_configs(state)
      state.added_node_entries.each do |entry|
        normalized = normalize_tool_config(state, node_type: entry[:node_type], config: entry[:raw_config])
        next if normalized == entry[:applied_config]

        state.editor.update_node(node_id: entry[:node_id], data: normalized)
        entry[:applied_config] = normalized
      end
    end

    def normalize_tool_config(state, node_type:, config:)
      normalized = normalize_config_hash(config)
      normalized = normalize_set_variable_config(node_type, normalized)
      rewrite_temp_variable_aliases(state, normalized)
    end

    def normalize_set_variable_config(node_type, config)
      return config unless node_type.to_s == "set_variable"
      return config if config["assignments"].present?

      assignments = extract_assignment_aliases(config)
      return config if assignments.blank?

      config.except("variables", "values").merge("assignments" => assignments)
    end

    def extract_assignment_aliases(config)
      variables = config["variables"]

      return variables.deep_stringify_keys if variables.is_a?(Hash)
      return extract_assignment_aliases_from_array(variables) if variables.is_a?(Array)
      return extract_assignment_aliases_from_string(config, variables) if variables.is_a?(String)
      return config["values"].deep_stringify_keys if config["values"].is_a?(Hash)

      {}
    rescue JSON::ParserError
      {}
    end

    def extract_assignment_aliases_from_array(entries)
      Array(entries).each_with_object({}) do |entry, assignments|
        next unless entry.is_a?(Hash)

        key, value = normalize_assignment_alias_entry(entry)
        next if key.blank? || value.nil?

        assignments[key] = value
      end
    end

    def normalize_assignment_alias_entry(entry)
      normalized = entry.deep_stringify_keys
      key = normalized["name"].presence || normalized["key"].presence || normalized["variable_name"].presence
      value = normalized["value"]
      value = normalized["expression"] if value.nil?
      [key, value]
    end

    def extract_assignment_aliases_from_string(config, raw_variables)
      parsed = JSON.parse(raw_variables)
      extract_assignment_aliases(config.merge("variables" => parsed))
    end

    def rewrite_temp_variable_aliases(state, value)
      case value
      when Hash
        value.transform_values { |nested| rewrite_temp_variable_aliases(state, nested) }
      when Array
        value.map { |nested| rewrite_temp_variable_aliases(state, nested) }
      when String
        rewrite_temp_variable_aliases_in_string(state, value)
      else
        value
      end
    end

    def rewrite_temp_variable_aliases_in_string(state, value)
      state.temp_variables.each do |temp_id, variable_name|
        next if temp_id.blank? || variable_name.blank? || temp_id == variable_name

        updated = value.gsub(/(?<![A-Za-z0-9_])#{Regexp.escape(temp_id)}\./, "#{variable_name}.")
        next if updated == value

        remember_rewritten_temp_id(state, temp_id, variable_name)
        value = updated
      end

      value
    end

    def remember_rewritten_temp_id(state, temp_id, variable_name)
      rewritten_pair = [temp_id, variable_name]
      return if state.rewritten_temp_ids.include?(rewritten_pair)

      state.rewritten_temp_ids << rewritten_pair
    end

    def first_present_value(*values)
      values.find(&:present?)
    end

    def first_present_from(primary, secondary, primary_keys:, secondary_keys: primary_keys)
      first_present_value(*values_for(primary, primary_keys), *values_for(secondary, secondary_keys))
    end

    def values_for(source, keys)
      Array(keys).map { |key| source[key] }
    end

    def current_node_type(mission, node_id)
      mission.reload.flow_data.to_h.fetch("nodes", []).find { |node| node["id"] == node_id }.to_h["type"]
    end

    def resolve_ref(state, ref)
      value = extract_ref_value(ref)
      return nil if value.blank?

      state.temp_ids.fetch(value, value)
    end

    def extract_ref_value(raw_ref)
      return raw_ref unless raw_ref.is_a?(Hash)

      ref = normalize_hash(raw_ref)
      first_present_value(
        ref["id"],
        ref["node_id"],
        ref["node_ref"],
        ref["ref"],
        ref["source"],
        ref["source_id"],
        ref["source_node_id"],
        ref["source_ref"],
        ref["from"],
        ref["target"],
        ref["target_id"],
        ref["target_node_id"],
        ref["target_ref"],
        ref["to"],
      )
    end
  end
end
