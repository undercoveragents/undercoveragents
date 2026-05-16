# frozen_string_literal: true

# JSONB-backed ActiveModel configurator for RAG Query tools.
# Data lives in `tools.configuration` JSONB column — no separate table.
module Tools
  class RagQuery
    include UndercoverAgents::PluginSystem::Configurator
    include ToolWidgetConfigurable
    include ToolPlugin
    include Tools::RagSearchable

    TOOL_DESIGNER_EDITABLE_ATTRIBUTES = [
      "connector_id",
      "llm_connector_id",
      "chunks_table",
      "documents_table",
      "chunk_content_field",
      "embedding_field",
      "document_reference_field",
      "distance_method",
      "document_fields",
      "custom_instructions",
      "max_distance",
      "results_limit",
      "embedding_model_id",
      *ToolWidgetConfigurable::DESIGNER_ATTRIBUTE_KEYS,
    ].freeze

    TOOL_DESIGNER_NOTES = [
      "Use list_resources(kind: \"sql_database_connectors\") for connector_id and " \
      "list_resources(kind: \"llm_connectors\") for llm_connector_id.",
      "Use list_resources(kind: \"models\", connector_id: ...) to resolve embedding model IDs exactly.",
      "Run discover before choosing tables and fields so the schema comes from the live database.",
    ].freeze

    attr_accessor :_tool_record

    attribute :connector_id, :integer
    attribute :llm_connector_id, :integer
    attribute :chunks_table, :string
    attribute :documents_table, :string
    attribute :chunk_content_field, :string, default: "content"
    attribute :embedding_field, :string, default: "embedding"
    attribute :document_reference_field, :string, default: "document_id"
    attribute :distance_method, :string, default: "cosine"
    attribute :document_fields, default: -> { [] }
    attribute :discovered_schema, default: -> { {} }
    attribute :custom_instructions, :string
    attribute :max_distance, :float, default: 0.8
    attribute :results_limit, :integer, default: 10
    attribute :embedding_model_id, :string
    attribute :schema_discovered_at, :datetime

    validates :chunks_table, presence: true, length: { maximum: 200 }
    validates :documents_table, presence: true, length: { maximum: 200 }
    validates :chunk_content_field, presence: true, length: { maximum: 200 }
    validates :embedding_field, presence: true, length: { maximum: 200 }
    validates :document_reference_field, presence: true, length: { maximum: 200 }
    validates :embedding_model_id, presence: true, length: { maximum: 200 }, if: :llm_connector_id?
    validate :connector_must_be_sql_database
    validate :llm_connector_must_be_llm_provider

    def self.type_key = "rag_query"
    def self.type_label = "RAG Query"
    def self.type_icon = "fa-solid fa-magnifying-glass"

    def self.tool_widget_default_presentation(display_name:, icon:)
      ToolCalls::Presentation.new(
        display_name:,
        icon:,
        running_messages: [
          "Searching the knowledge base…", "Scoring semantic matches…", "Collecting the most relevant chunks…",
        ],
        complete_messages: ["Relevant passages gathered.", "Semantic search completed.", "Knowledge hits are ready."],
      )
    end

    def self.tool_designer_editable_attributes = TOOL_DESIGNER_EDITABLE_ATTRIBUTES

    def self.tool_designer_notes = TOOL_DESIGNER_NOTES

    def self.tool_designer_field_hints
      {
        "connector_id" => resource_hint("sql_database_connectors"),
        "llm_connector_id" => resource_hint("llm_connectors"),
        "embedding_model_id" => resource_hint("models", note: "Pass connector_id: llm_connector_id."),
      }
    end

    def self.tool_designer_state_attributes
      [
        tool_designer_state_attribute(label: "Schema discovered at", method: :schema_discovered_at),
        tool_designer_state_attribute(label: "Discovered tables", method: :all_discovered_table_names),
      ]
    end

    def self.runtime_tool_adapter_class_name = "RagQueryTool"

    def self.permitted_params(params)
      raw = permit_params_with_widget(
        params,
        [:connector_id, :custom_instructions, :chunks_table, :documents_table,
         :chunk_content_field, :embedding_field, :document_reference_field,
         :distance_method, :max_distance, :results_limit,
         :llm_connector_id, :model_id, { document_fields: [] },],
      ).to_h.symbolize_keys
      # model_select partial sends model_id; map it to embedding_model_id
      raw[:embedding_model_id] = raw.delete(:model_id) if raw.key?(:model_id)
      raw
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def connector
      return @connector_instance if defined?(@connector_instance) && @connector_instance&.id == connector_id

      @connector_instance = connector_id.present? ? find_connector(connector_id) : nil
    end

    def connector=(record)
      self.connector_id = record&.id
      @connector_instance = record
    end

    def llm_connector
      if defined?(@llm_connector_instance) && @llm_connector_instance&.id == llm_connector_id
        return @llm_connector_instance
      end

      @llm_connector_instance = llm_connector_id.present? ? find_connector(llm_connector_id) : nil
    end

    def llm_connector=(record)
      self.llm_connector_id = record&.id
      @llm_connector_instance = record
    end

    def perform_discovery!
      result = ::Tools::SchemaDiscoverer.new(sql_database).call

      if result.success?
        self.discovered_schema = result.schema
        self.schema_discovered_at = Time.current
        save!
        ToolPlugin::Result.new(success?: true, message: I18n.t("tools.schema_discovered"))
      else
        ToolPlugin::Result.new(success?: false, message: result.message)
      end
    end

    def visibility_available?
      schema_discovered?
    end

    def sql_database
      connector
    end

    def schema_discovered?
      schema_discovered_at.present? && discovered_schema.present?
    end

    def chunks_columns
      extract_table_columns(chunks_table)
    end

    def documents_columns
      extract_table_columns(documents_table)
    end

    def all_discovered_table_names
      return [] unless discovered_schema.is_a?(Hash)

      (discovered_schema["objects"] || []).pluck("name")
    end

    def llm_connector_id?
      llm_connector_id.present?
    end

    private

    def extract_table_columns(table_name)
      return [] unless discovered_schema.is_a?(Hash)

      objects = discovered_schema["objects"] || []
      table = objects.find { |obj| obj["name"] == table_name }
      return [] unless table

      (table["columns"] || []).pluck("name")
    end

    def connector_must_be_sql_database
      return if connector_id.blank?
      return errors.add(:connector, "must be an SQL Database connector") if connector.blank?
      return if connector.connector_type == "sql_database"

      errors.add(:connector, "must be an SQL Database connector")
    end

    def llm_connector_must_be_llm_provider
      return if llm_connector_id.blank?
      return if llm_connector&.connector_type == "llm_provider"

      errors.add(:llm_connector_id, "must be an LLM Provider connector")
    end
  end
end
