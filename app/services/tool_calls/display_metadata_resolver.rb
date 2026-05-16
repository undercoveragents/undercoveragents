# frozen_string_literal: true

module ToolCalls
  class DisplayMetadataResolver
    Result = ToolCalls::Presentation

    DEFAULT_ICON = "fa-solid fa-wrench"
    FALLBACK_ICON_PATTERNS = [
      [/\Aask_agent_/, "fa-solid fa-robot"],
      [/\Asql_/, "fa-solid fa-database"],
      [/\Aarchival_memory_/, "fa-solid fa-box-archive"],
      [/memory/, "fa-solid fa-brain"],
      [/skill/, "fa-solid fa-book-open"],
      [/mission|node|edge|flow/, "fa-solid fa-diagram-project"],
      [/test/, "fa-solid fa-vial"],
    ].freeze
    ACRONYMS = {
      "api" => "API",
      "id" => "ID",
      "llm" => "LLM",
      "mcp" => "MCP",
      "rag" => "RAG",
      "sql" => "SQL",
      "ui" => "UI",
    }.freeze

    def self.resolve(name, chat: nil)
      new(name, chat:).resolve
    end

    # Locates the user-created Tool record that owns the runtime tool name for
    # the given chat. Used by compaction and presentation layers that need to
    # read configurator-backed settings (e.g. tool_compaction_policy).
    def self.tool_record_for(name, chat:)
      new(name, chat:).send(:matching_tool_record)
    end

    def initialize(name, chat: nil)
      @name = name.to_s
      @chat = chat
    end

    def resolve
      return fallback_result(display_name: "Tool Call", icon: DEFAULT_ICON) if name.blank?

      builtin_metadata || configured_tool_metadata || subagent_metadata || fallback_metadata
    end

    private

    attr_reader :chat, :name

    def builtin_metadata
      definition = BuiltinTools::Registry.definition_for_runtime_name(name)
      return unless definition

      ToolCalls::PresentationDefaults.for_builtin(definition).with(icon: definition.icon.presence || fallback_icon)
    end

    def configured_tool_metadata
      tool_record = matching_tool_record
      return unless tool_record

      display_name = nil
      display_name = tool_display_name(tool_record)
      ToolCalls::PresentationDefaults.resolve_user_tool(
        tool_type: tool_record.tool_type,
        display_name:,
        icon: tool_record.type_icon,
        toolable: tool_record.toolable,
        toolable_class: tool_record.toolable.class,
      )
    rescue StandardError
      fallback_result(display_name:, icon: tool_record.type_icon)
    end

    def subagent_metadata
      subagent = candidate_subagents.find { |agent| subagent_runtime_name(agent) == name }
      return unless subagent

      ToolCalls::PresentationDefaults.for_subagent(name: subagent.name)
    end

    def fallback_metadata
      fallback_result(display_name: humanize_runtime_name(name), icon: fallback_icon)
    end

    def candidate_tool_records
      return [] unless chat&.agent

      @candidate_tool_records ||= chat.agent.assigned_tools.enabled.to_a
    end

    def matching_tool_record
      @matching_tool_record ||= candidate_tool_records.find { |record| matches_tool_record?(record) }
    end

    def candidate_subagents
      return [] unless chat&.agent

      @candidate_subagents ||= chat.agent.subagents.enabled.to_a
    end

    def matches_tool_record?(tool_record)
      toolable = toolable_for(tool_record)
      tool_class = resolve_tool_class(tool_record, toolable)
      return false unless tool_class.respond_to?(:tool_runtime_names)

      Array(tool_class.tool_runtime_names(tool_record:, toolable:)).include?(name)
    rescue StandardError
      false
    end

    def tool_display_name(tool_record)
      toolable = toolable_for(tool_record)
      tool_class = resolve_tool_class(tool_record, toolable)
      display_name = tool_class&.tool_runtime_display_name(runtime_name: name, tool_record:, toolable:)

      display_name.presence || humanize_runtime_name(name)
    end

    def subagent_runtime_name(agent)
      "ask_agent_#{sanitize_fragment(agent.name)}"
    end

    def sanitize_fragment(value)
      value.to_s
           .unicode_normalize(:nfkd)
           .encode("ASCII", replace: "")
           .gsub(/[^a-zA-Z0-9_-]/, "_")
           .squeeze("_")
           .gsub(/\A_|_\z/, "")
           .downcase
    end

    def toolable_for(tool_record)
      tool_record.toolable
    rescue StandardError
      nil
    end

    def resolve_tool_class(tool_record, toolable)
      toolable_class = toolable&.class
      return toolable_class if toolable_class.respond_to?(:tool_runtime_names)

      ToolPlugin.resolve(tool_record.tool_type)
    end

    def humanize_runtime_name(value)
      words = value.to_s.split(/[._-]+/).compact_blank
      return value.to_s.humanize if words.empty?

      words.map { |word| ACRONYMS.fetch(word.downcase, word.humanize) }.join(" ")
    end

    def fallback_icon
      FALLBACK_ICON_PATTERNS.each do |pattern, icon|
        return icon if pattern.match?(name)
      end

      DEFAULT_ICON
    end

    def fallback_result(display_name:, icon:)
      ToolCalls::PresentationDefaults.for_fallback(display_name:, icon:)
    end
  end
end
