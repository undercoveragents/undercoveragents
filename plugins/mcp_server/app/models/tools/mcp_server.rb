# frozen_string_literal: true

# JSONB-backed ActiveModel configurator for MCP Server tools.
# Data lives in `tools.configuration` JSONB column — no separate table.
module Tools
  class McpServer
    include UndercoverAgents::PluginSystem::Configurator
    include ToolWidgetConfigurable
    include ToolPlugin

    attr_accessor :_tool_record

    attribute :connector_id, :integer
    attribute :discovered_tools, default: -> { [] }
    attribute :selected_tools, default: -> { [] }
    attribute :tools_discovered_at, :datetime

    validate :connector_must_be_mcp_server

    # ── Tool Type Protocol ────────────────────────────────────────

    def self.type_key = "mcp_server"
    def self.type_label = "MCP Server"
    def self.type_icon = "fa-solid fa-server"

    def self.tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(
        display_name:,
        icon:,
        running_messages: [
          "Calling the external tool…",
          "Waiting for the MCP server…",
          "Collecting the server response…",
        ],
        complete_messages: [
          "External tool response received.",
          "MCP call completed.",
          "Server output is ready.",
        ],
      )
    end

    def self.tool_designer_editable_attributes
      [
        "connector_id",
        *ToolWidgetConfigurable::DESIGNER_ATTRIBUTE_KEYS,
      ]
    end

    def self.tool_designer_notes
      [
        "Use list_resources(kind: \"mcp_server_connectors\") to resolve connector_id values.",
        "Run discover before set_visibility so the available MCP tool names come from the real server.",
        "selected_tools is managed through the set_visibility action after discovery instead of direct updates.",
      ]
    end

    def self.tool_designer_field_hints
      {
        "connector_id" => resource_hint("mcp_server_connectors"),
      }
    end

    def self.tool_designer_state_attributes
      [
        tool_designer_state_attribute(label: "Tools discovered at", method: :tools_discovered_at),
        tool_designer_state_attribute(label: "Visible tools", method: :selected_tool_names, empty: true),
        tool_designer_state_attribute(label: "Discovered tools", method: :all_discovered_tool_names),
      ]
    end

    def self.runtime_tool_adapter_class_name = "McpServerTool"

    def self.tool_runtime_names(tool_record:, toolable: nil)
      _ = tool_record

      selected = Array(toolable&.selected_tool_names)
      discovered = Array(toolable&.all_discovered_tool_names)
      (selected + discovered).compact_blank.uniq
    end

    def self.tool_runtime_display_name(runtime_name:, tool_record:, toolable: nil)
      _ = runtime_name
      _ = tool_record
      _ = toolable

      nil
    end

    def self.permitted_params(params)
      permit_params_with_widget(params, [:connector_id])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Connector accessor ────────────────────────────────────────

    def connector
      # :nocov:
      return @connector_instance if defined?(@connector_instance) && @connector_instance&.id == connector_id
      # :nocov:

      @connector_instance = connector_id.present? ? find_connector(connector_id) : nil
    end

    def connector=(record)
      self.connector_id = record&.id
      @connector_instance = record
    end

    def perform_discovery!
      result = ::Tools::McpToolDiscoverer.new(mcp_server).call

      if result.success?
        previous_names = selected_tool_names
        self.discovered_tools = result.tools
        self.tools_discovered_at = Time.current
        sync_selected_after_discovery(previous_names)
        save!
        ToolPlugin::Result.new(
          success?: true,
          message: I18n.t("tools.tools_discovered", count: result.tools.size),
        )
      else
        ToolPlugin::Result.new(success?: false, message: result.message)
      end
    end

    def update_visibility!(raw_params)
      names = Array(raw_params.dig(:mcp_server, :selected_tools))
      update!(selected_tools: names.map { |name| { "name" => name } })
    end

    def visibility_param_key = "selected_tools"

    def visibility_available?
      tools_discovered?
    end

    # ── MCP-specific methods ──────────────────────────────────────

    def selected_tool_names
      return [] unless selected_tools.is_a?(Array)

      selected_tools.filter_map { |t| t["name"] || t[:name] }
    end

    def all_discovered_tool_names
      return [] unless discovered_tools.is_a?(Array)

      discovered_tools.filter_map { |t| t["name"] || t[:name] }
    end

    def all_tools_selected?
      names = all_discovered_tool_names
      return true if names.empty?

      (names - selected_tool_names).empty?
    end

    def sync_selected_after_discovery(previous_selected_names = [])
      current_names = all_discovered_tool_names
      if previous_selected_names.empty?
        self.selected_tools = current_names.map { |n| { "name" => n } }
      else
        kept = previous_selected_names & current_names
        added = current_names - previous_selected_names
        self.selected_tools = (kept + added).map { |n| { "name" => n } }
      end
    end

    def tools_discovered?
      tools_discovered_at.present? && discovered_tools.present?
    end

    def mcp_server
      connector
    end

    private

    def connector_must_be_mcp_server
      return if connector_id.blank?
      return errors.add(:connector, "must be an MCP Server connector") if connector.blank?
      return if connector.connector_type == "mcp_server"

      errors.add(:connector, "must be an MCP Server connector")
    end
  end
end
