# frozen_string_literal: true

module MissionDesigner
  # Reads the current mission flow. Defaults to a compact representation
  # (ids + type + label + 1-line config). Pass detail: 'full' for the
  # untruncated view, or node_ids: ["node-abc", ...] to drill into specific nodes.
  class ReadFlowTool < BaseTool
    description "Returns the current mission flow. Default is a compact summary. " \
                "Pass detail='full' for everything, or node_ids as a comma-separated list for deep detail. " \
                "Pass mission_id to inspect a mission created earlier in the same turn."

    param :detail, desc: "Level of detail: 'compact' (default) or 'full'.", required: false
    param :node_ids, desc: "Optional comma-separated list of node IDs to expand (overrides detail).",
                     required: false
    param :mission_id,
          desc: "Optional mission ID or slug to inspect. Use this after creating a mission in the same turn.",
          required: false

    def name
      "read_mission_flow"
    end

    def execute(detail: nil, node_ids: nil, mission_id: nil)
      mission = resolve_target_mission(mission_id)
      editor = Missions::FlowEditor.new(mission)
      result = editor.read_flow
      expanded_ids = parse_node_ids(node_ids)
      format_result(result, detail:, expanded_ids:)
    rescue StandardError => e
      "Error reading flow: #{e.message}"
    end

    private

    def parse_node_ids(raw)
      return [] if raw.blank?

      raw.to_s.split(",").map(&:strip).compact_blank
    end

    def format_result(result, detail:, expanded_ids:)
      mode = resolve_mode(detail, expanded_ids)
      parts = []
      format_global_variables(parts, result[:global_variables], mode)
      format_nodes(parts, result[:nodes], mode, expanded_ids)
      parts << ""
      format_edges(parts, result[:edges])
      format_validation_errors(parts, result[:validation_errors])
      parts.join("\n")
    end

    def resolve_mode(detail, expanded_ids)
      return :partial if expanded_ids.any?
      return :full if detail.to_s == "full"

      :compact
    end

    def format_global_variables(parts, vars, mode)
      return if vars.blank?

      parts << "## Global Variables (#{vars.size})"
      if mode == :compact
        parts << "- keys: #{vars.pluck("key").join(", ")}"
      else
        vars.each { |var| parts << "- **#{var["key"]}** = `#{var["value"]}` (type: #{var["type"]})" }
      end
      parts << ""
    end

    def format_nodes(parts, nodes, mode, expanded_ids)
      parts << "## Nodes (#{nodes.size})"
      if nodes.empty?
        parts << "No nodes yet."
        return
      end

      nodes.each do |node|
        parts << format_single_node(node, mode, expanded_ids)
      end
    end

    def format_single_node(node, mode, expanded_ids)
      expand = mode == :full || (mode == :partial && expanded_ids.include?(node[:id]))
      if expand
        config_str = node[:config].compact_blank.map { |k, v| "#{k}=#{truncate_value(v)}" }.join(", ")
        var_str = node[:variable_name].present? ? " var_prefix=`#{node[:variable_name]}`" : ""
        "- **#{node[:name]}** (id: `#{node[:id]}`, type: `#{node[:type]}`)#{var_str} #{config_str}"
      else
        summary = compact_summary(node[:config])
        "- `#{node[:id]}` #{node[:type]} — #{node[:name]}#{" (#{summary})" if summary.present?}"
      end
    end

    def compact_summary(config)
      return "" if config.blank?

      filled = config.compact_blank.keys.first(3)
      filled.join(", ")
    end

    def format_edges(parts, edges)
      parts << "## Edges (#{edges.size})"
      if edges.empty?
        parts << "No connections yet."
      else
        edges.each do |edge|
          parts << "- `#{edge[:source]}` → `#{edge[:target]}` (port: #{edge[:source_port]}, id: `#{edge[:id]}`)"
        end
      end
    end

    def format_validation_errors(parts, errors)
      return unless errors.any?

      parts << ""
      parts << "## Validation Errors"
      errors.each do |node_id, errs|
        errs.each { |err| parts << "- Node `#{node_id}`: #{err[:message]} (field: #{err[:field]})" }
      end
    end

    def truncate_value(value)
      str = value.to_s
      str.length > 80 ? "#{str[0..77]}..." : str
    end
  end
end
