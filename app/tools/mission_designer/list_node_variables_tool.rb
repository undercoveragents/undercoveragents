# frozen_string_literal: true

module MissionDesigner
  # Lists variables available at a specific node in the mission flow.
  # Uses VariableRegistry to compute upstream variables reachable at the node,
  # filtering out internal (_-prefixed) variables.
  class ListNodeVariablesTool < BaseTool
    DESCRIPTION = [
      "Lists upstream variables (name + type) reachable at one or more nodes.",
      "When validation reports an unknown variable or output reference, call this and reuse the " \
      "returned variable identifiers exactly.",
      "Wrap those identifiers in `{{...}}` only for template-valued fields; keep them bare in " \
      "formulas, collection refs, selected_variables, and test expectations.",
      "Batch related lookups with node_ids to reduce tool calls.",
      "Pass mission_id after creating a mission in the same turn.",
    ].join(" ").freeze
    MISSING_MISSION_MESSAGE = [
      "Mission context is required before listing node variables.",
      "Create or open a mission first, or pass mission_id after creating a mission in the same turn.",
    ].join(" ").freeze

    description DESCRIPTION

    param :node_id, desc: "The ID of one node to inspect (e.g. 'node-abc123')", required: false
    param :node_ids,
          desc: "Optional array, JSON array string, or comma-separated list of node IDs to inspect in one call.",
          required: false
    param :mission_id,
          desc: "Optional mission ID or slug to inspect. Use this after creating a mission in the same turn.",
          required: false

    def name
      "list_node_variables"
    end

    def execute(node_id: nil, node_ids: nil, mission_id: nil)
      mission = resolve_mission(mission_id)
      requested_node_ids = normalize_node_ids(node_id, node_ids)
      return "Provide node_id or node_ids." if requested_node_ids.empty?

      flow_data = mission.flow_data || {}
      registry = Missions::VariableRegistry.new(flow_data)
      return format_variables_for_node(registry, requested_node_ids.first) if requested_node_ids.one?

      requested_node_ids
        .map { |current_node_id| format_variables_for_node(registry, current_node_id, allow_empty: true) }
        .join("\n\n")
    rescue ArgumentError => e
      e.message
    rescue StandardError => e
      "Error listing variables: #{e.message}"
    end

    private

    def missing_mission_message
      MISSING_MISSION_MESSAGE
    end

    def resolve_mission(mission_id)
      resolve_target_mission(mission_id, missing_message: missing_mission_message)
    end

    def normalize_node_ids(node_id, node_ids)
      ([node_id] + parse_node_ids(node_ids)).map { |value| value.to_s.strip }.compact_blank.uniq
    end

    def parse_node_ids(raw)
      case raw
      when nil
        []
      when Array
        raw
      else
        string_value = raw.to_s.strip
        return [] if string_value.blank?

        parse_structured_node_ids(string_value) || string_value.split(",")
      end
    end

    def parse_structured_node_ids(value)
      parsed = JSON.parse(value)
      parsed.is_a?(Array) ? parsed : nil
    rescue JSON::ParserError
      nil
    end

    def format_variables_for_node(registry, node_id, allow_empty: false)
      entries = registry.available_at(node_id)
      selectable = entries.reject { |entry| entry.name.start_with?("_") }

      if selectable.empty?
        return "## Variables available at node `#{node_id}` (0)\n\nNo variables available." if allow_empty

        return "No variables available at node `#{node_id}`."
      end

      format_variables(node_id, selectable)
    end

    def format_variables(node_id, selectable)
      parts = intro_lines(node_id, selectable.size)
      append_collection_hint(parts, selectable)
      append_results_hint(parts, selectable)
      selectable.each do |entry|
        parts << format_entry(entry)
      end
      parts.join("\n")
    end

    def intro_lines(node_id, count)
      [
        "## Variables available at node `#{node_id}` (#{count})",
        "",
        "Use these names exactly as shown as variable identifiers.",
        "Do not use temp_id values, raw node IDs, or guessed normalized labels unless " \
        "one of the names below matches exactly.",
        "For template-valued fields such as `json_extract.source`, `http_request.url`, " \
        "`llm.prompt`, or `output.response_body`, wrap the identifier in `{{...}}`.",
        "For non-template fields such as `selected_variables`, mission test expectations, " \
        "collection refs, or formulas, keep the identifier bare.",
        "If validation reports an unknown variable or output reference,",
        "do not guess alternate syntaxes; reuse one of the names below as the identifier and " \
        "only change the surrounding template syntax when the field kind requires it.",
        "Prefer fully qualified names like `node_prefix.variable` unless the variable is explicitly global.",
        "Duplicate node labels receive numeric suffixes in their prefixes (for example `json_extract_2`).",
      ]
    end

    def append_collection_hint(parts, selectable)
      return unless selectable.any? { |entry| collection_like_entry?(entry) }

      parts << "Array and object variables interpolate in templates, but mission formulas only " \
               "evaluate scalar numbers, strings, and booleans. Extract a scalar field, count, " \
               "or other derived value before comparing them in expressions."
    end

    def append_results_hint(parts, selectable)
      return unless selectable.any? { |entry| results_entry?(entry) }

      parts << "If you are working off an iterator or loop done branch, inspect any `results` " \
               "entry carefully before aggregating or comparing it in formulas; it may be an " \
               "array of objects rather than a flat array of scalars."
    end

    def collection_like_entry?(entry)
      [:array, :hash, :object].include?(entry.type&.to_sym)
    end

    def results_entry?(entry)
      names = [entry.name, entry.qualified_name].compact
      names.any? { |name| name == "results" || name.end_with?(".results") }
    end

    def format_entry(entry)
      source = entry.qualified_name || entry.name
      desc = entry.description.present? ? " — #{entry.description}" : ""
      "- `#{source}` (#{entry.type})#{desc}"
    end
  end
end
