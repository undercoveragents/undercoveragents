# frozen_string_literal: true

# Single entry point for discovering operation-scoped resource IDs and values
# across builtin designer runtimes.
class ListResourcesTool < RubyLLM::Tool
  include ListResourcesToolContext
  include ListResourcesToolCoreResources
  include ListResourcesToolPluginResources

  CORE_KINDS_DESCRIPTION = "Core kinds: agent_types, capabilities, models, default_models, tool_types, " \
                           "tools, agents, missions, channels, clients, skill_catalogs, skills, " \
                           "rag_flows, connectors, test_suites."
  DEFAULT_DESCRIPTION = [
    "List operation-scoped resource IDs and values for one or more core or plugin-declared kinds.",
    "Use this when you need exact IDs, enums, available kinds, or workspace inventory.",
    "Do not use it as a preflight step when another tool or sub-agent can execute the task directly.",
    "Use kind: \"skill_catalogs\" for configured workspace skill-catalog records instead of list_available_skills.",
    CORE_KINDS_DESCRIPTION,
    "Omit kind/kinds to see the currently available kinds.",
  ].join(" ").freeze

  description DEFAULT_DESCRIPTION

  param :kind,
        desc: "A resource kind to list. #{CORE_KINDS_DESCRIPTION} Omit it to see the currently available kinds.",
        required: false

  param :kinds,
        desc: "Optional array of resource kinds when you need multiple collections in one call. " \
              "#{CORE_KINDS_DESCRIPTION}",
        type: :array,
        required: false

  param :connector_id,
        desc: "Optional connector id. Use when kind includes 'models'.",
        required: false

  CORE_KIND_HANDLERS = {
    "agent_types" => :agent_types,
    "capabilities" => :capabilities,
    "models" => :models,
    "default_models" => :default_models,
    "tool_types" => :tool_types,
    "tools" => :tools,
    "agents" => :agents,
    "missions" => :missions,
    "channels" => :channels,
    "clients" => :clients,
    "skill_catalogs" => :skill_catalogs,
    "skills" => :skills,
    "rag_flows" => :rag_flows,
    "connectors" => :connectors,
    "test_suites" => :test_suites,
  }.freeze

  def initialize(mission = nil, runtime_context: nil, current_agent: nil)
    super()
    @mission = mission
    @runtime_context = runtime_context
    @current_agent = current_agent
  end

  def name = "list_resources"

  def execute(kind: nil, kinds: nil, connector_id: nil)
    requested_kinds = normalize_requested_kinds(kind:, kinds:)
    return available_kinds_message if requested_kinds.empty?

    sections = requested_kinds.map { |requested_kind| render_kind(requested_kind, connector_id:) }
    return sections.first if sections.one?

    sections.join("\n\n")
  rescue StandardError => e
    "Error listing resources: #{e.message}"
  end

  private

  def normalize_requested_kinds(kind:, kinds:)
    [kind, kinds]
      .flatten
      .compact
      .flat_map { |value| value.to_s.split(",") }
      .map(&:strip)
      .compact_blank
      .uniq
  end

  def render_kind(kind, connector_id:)
    handler = CORE_KIND_HANDLERS[kind]
    return render_connector_kind(kind) if connector_resource_definitions.key?(kind)
    return render_registered_resource_kind(kind) if registered_resource_definitions.key?(kind)
    return unknown_kind_message(kind) unless handler

    handler == :models ? send(handler, connector_id) : send(handler)
  end

  def unknown_kind_message(kind)
    "Unknown kind: '#{kind}'. Use one of: #{valid_kinds.join(", ")}."
  end

  def valid_kinds
    @valid_kinds ||= (
      CORE_KIND_HANDLERS.keys + connector_resource_definitions.keys + registered_resource_definitions.keys
    ).uniq.sort
  end

  def available_kinds_message
    [
      *context_summary_lines,
      "Available resource kinds:",
      "- Core: #{CORE_KIND_HANDLERS.keys.join(", ")}",
      ("- Plugin-defined: #{plugin_defined_kinds.join(", ")}" if plugin_defined_kinds.any?),
      "Use kind: \"...\" or kinds: [\"...\", \"...\"] to fetch concrete IDs and values.",
      "Use connector_id when kind includes \"models\".",
    ].compact.join("\n")
  end

  def plugin_defined_kinds
    @plugin_defined_kinds ||= (connector_resource_definitions.keys + registered_resource_definitions.keys).uniq.sort
  end
end
