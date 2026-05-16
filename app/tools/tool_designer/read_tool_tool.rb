# frozen_string_literal: true

module ToolDesigner
  class ReadToolTool < RubyLLM::Tool
    include ToolLookup

    description "Inspect the current tool configuration or another tool in the current operation."

    param :tool_id,
          desc: "Optional numeric ID or slug. Omit to inspect the current tool from page context.",
          required: false

    def initialize(runtime_context:, current_tool: nil)
      super()
      @runtime_context = runtime_context
      @current_tool = current_tool
    end

    def name = "read_tool"

    def execute(tool_id: nil)
      tool = resolve_tool(tool_id)
      return missing_tool_message if tool.nil?

      [
        summary_section(tool),
        assignments_section(tool),
        state_section(tool),
        configuration_section(tool),
        ToolDesigner::TypeCatalog.new(tool.tool_type).render,
      ].compact.join("\n\n")
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading tool: #{e.message}"
    end

    private

    def summary_section(tool)
      [
        "## Tool",
        "- ID: `#{tool.id}`",
        "- Name: #{tool.name}",
        "- Slug: `#{tool.slug}`",
        "- Description: #{tool.description.presence || "None"}",
        "- Type: `#{tool.tool_type}` — #{tool.type_label}",
        "- Enabled: #{tool.enabled?}",
        "- Operation: #{tool.operation.name} (`#{tool.operation.slug}`)",
      ].join("\n")
    end

    def assignments_section(tool)
      agents = assigned_agents(tool)
      return "## Assigned Agents\n- None" if agents.empty?

      lines = ["## Assigned Agents"]
      agents.each { |agent| lines << "- `#{agent.id}` — #{agent.name}" }
      lines.join("\n")
    end

    def state_section(tool)
      state_lines = tool_state_lines(tool)
      return if state_lines.empty?

      ["## Current Tool State", *state_lines].join("\n")
    end

    def tool_state_lines(tool)
      Array(tool.toolable.tool_designer_state).filter_map do |entry|
        tool_state_line(entry)
      end
    end

    def configuration_section(tool)
      configuration = tool.configuration.presence || {}
      "## Current Configuration\n```json\n#{JSON.pretty_generate(configuration)}\n```"
    end

    def assigned_agents(tool)
      Agent.where(operation: tool.operation)
           .ordered
           .select { |agent| agent.assigned_tool_ids.include?(tool.id) }
    end

    def tool_state_line(entry)
      normalized_entry = entry.to_h.stringify_keys
      label = normalized_entry["label"].to_s.presence
      return if label.blank?

      "- #{label}: #{format_state_value(normalized_entry["value"])}"
    end

    def format_state_value(value)
      return "none" if value.blank?
      return value.map { |item| "`#{item}`" }.join(", ") if value.is_a?(Array)
      return "`#{JSON.generate(value)}`" if value.is_a?(Hash)

      "`#{value}`"
    end
  end
end
