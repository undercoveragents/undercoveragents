# frozen_string_literal: true

# JSONB-backed ActiveModel configurator for SQL Query tools.
# Data lives in `tools.configuration` JSONB column — no separate table.
module Tools
  class SqlQuery
    include UndercoverAgents::PluginSystem::Configurator
    include ToolWidgetConfigurable
    include ToolPlugin
    include SqlQueryConnectorAccessors
    extend SqlQueryToolProtocol

    attr_accessor :_tool_record

    LLM_CONFIG_SOURCES = ["inherit", "custom"].freeze
    TEMPERATURE_RANGE = (0.0..2.0)

    attribute :connector_id, :integer
    attribute :llm_connector_id, :integer
    attribute :instructions, :string
    attribute :llm_config_source, :string, default: "inherit"
    attribute :model_id, :string
    attribute :temperature, :float
    attribute :discovered_schema, default: -> { {} }
    attribute :selected_objects, default: -> { [] }
    attribute :schema_discovered_at, :datetime

    validates :instructions, length: { maximum: 10_000 }
    validates :llm_config_source, presence: true, inclusion: { in: LLM_CONFIG_SOURCES }
    validates :model_id, presence: true, length: { maximum: 200 }, if: :use_custom_llm_config?
    validates :temperature, presence: true,
                            numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0 },
                            if: :use_custom_llm_config?
    validate :connector_must_be_sql_database
    validate :llm_connector_must_be_llm_provider

    # ── Domain methods ────────────────────────────────────────────

    def use_custom_llm_config?
      llm_config_source == "custom"
    end

    def tables
      extract_objects_by_type("table")
    end

    def views
      extract_objects_by_type("view")
    end

    def materialized_views
      extract_objects_by_type("materialized_view")
    end

    def selected_object_names
      return [] unless selected_objects.is_a?(Array)

      selected_objects.filter_map { |obj| obj["name"] || obj[:name] }
    end

    def all_discovered_object_names
      return [] unless discovered_schema.is_a?(Hash)

      (discovered_schema["objects"] || []).pluck("name")
    end

    def all_objects_selected?
      names = all_discovered_object_names
      return true if names.empty?

      (names - selected_object_names).empty?
    end

    def sync_selected_after_discovery(previous_selected_names = [])
      current_names = all_discovered_object_names

      if previous_selected_names.empty?
        self.selected_objects = current_names.map { |n| { "name" => n } }
      else
        kept = previous_selected_names & current_names
        added = current_names - previous_selected_names
        self.selected_objects = (kept + added).map { |n| { "name" => n } }
      end
    end

    def schema_discovered?
      schema_discovered_at.present? && discovered_schema.present?
    end

    def sql_database
      connector
    end

    def effective_instructions
      instructions.presence || ::Tools::SqlToolInstructionsBuilder.call(self)
    end

    def instructions_editable? = true

    def auto_discover_after_create? = true

    def show_compaction_in_configuration_card? = true

    def perform_discovery!
      result = ::Tools::SchemaDiscoverer.new(sql_database).call

      if result.success?
        previous_names = selected_object_names
        self.discovered_schema = result.schema
        self.schema_discovered_at = Time.current
        sync_selected_after_discovery(previous_names)
        self.instructions = effective_instructions
        save!
        ToolPlugin::Result.new(success?: true, message: I18n.t("tools.schema_discovered"))
      else
        ToolPlugin::Result.new(success?: false, message: result.message)
      end
    end

    def update_visibility!(raw_params)
      names = Array(raw_params.dig(:sql_query, :selected_objects))
      self.selected_objects = names.map { |n| { "name" => n } }
      self.instructions = effective_instructions
      save!
    end

    def visibility_param_key = "selected_objects"

    def visibility_available?
      schema_discovered?
    end

    private

    def extract_objects_by_type(type)
      return [] unless discovered_schema.is_a?(Hash)

      Array(discovered_schema["objects"]).select { |object| object["type"] == type }
    end
  end
end
