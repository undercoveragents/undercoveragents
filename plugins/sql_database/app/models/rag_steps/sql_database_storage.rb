# frozen_string_literal: true

module RagSteps
  # Stores documents and chunks with embeddings in a PostgreSQL+pgvector database.
  class SqlDatabaseStorage
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include SqlDatabaseStorageWizard

    PRE_LOAD_ACTIONS = ["none", "truncate", "delete_matching"].freeze
    STORAGE_MODES = ["existing", "new"].freeze

    PRE_LOAD_ACTION_LABELS = {
      "none" => "None (append)",
      "truncate" => "Truncate tables",
      "delete_matching" => "Delete matching documents",
    }.freeze

    ALLOWED_COLUMN_TYPES = [
      "text", "varchar", "integer", "bigint", "smallint", "boolean",
      "timestamp", "timestamptz", "date", "numeric", "float", "uuid", "jsonb",
    ].freeze

    FORM_PARTIAL_PATH = File.expand_path("../../views/sql_database_storage", __dir__).freeze

    attribute :connector_id, :integer
    attribute :storage_mode, :string
    attribute :documents_table, :string
    attribute :chunks_table, :string
    attribute :content_field, :string, default: "content"
    attribute :embedding_field, :string, default: "embedding"
    attribute :document_reference_field, :string, default: "document_id"
    attribute :pre_load_action, :string, default: "none"
    attribute :upsert_enabled, :boolean, default: false
    attribute :auto_create_tables, :boolean, default: false
    attribute :embedding_dimensions, :integer, default: 1536
    attribute :metadata_column_types, default: -> { {} }
    attribute :metadata_field_mappings, default: -> { {} }

    validates :documents_table, presence: true, length: { maximum: 200 }
    validates :chunks_table, presence: true, length: { maximum: 200 }
    validates :content_field, presence: true, length: { maximum: 200 }
    validates :embedding_field, presence: true, length: { maximum: 200 }
    validates :document_reference_field, presence: true, length: { maximum: 200 }
    validates :pre_load_action, presence: true, inclusion: { in: PRE_LOAD_ACTIONS }
    validates :storage_mode, inclusion: { in: STORAGE_MODES }, allow_blank: true
    validates :embedding_dimensions, presence: true,
                                     numericality: { only_integer: true, greater_than: 0,
                                                     less_than_or_equal_to: 65_535, }
    validate :connector_must_be_sql_database
    validate :connector_must_support_postgresql_rag_storage
    validate :metadata_column_types_must_be_valid
    validate :table_names_must_differ
    validate :existing_tables_configuration_must_be_valid, if: :existing_tables_mode?
    before_validation :normalize_wizard_state

    # ── Step Type Protocol ────────────────────────────────────────

    key "sql_database_storage"
    label "SQL Database"
    icon "fa-solid fa-hard-drive"
    stage :storage
    description [
      "Store documents and embeddings in a PostgreSQL database with pgvector.",
      "Supports upsert and auto table creation.",
    ].join(" ")

    def self.permitted_params(params)
      params.expect(
        sql_database_storage: [:connector_id, :storage_mode, :documents_table, :chunks_table, :content_field,
                               :embedding_field, :document_reference_field, :pre_load_action,
                               :upsert_enabled, :auto_create_tables, :embedding_dimensions,
                               { metadata_field_mappings: {}, metadata_column_types: {} },],
      )
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def connector
      return @connector if defined?(@connector)

      @connector = find_connector(connector_id)
    end

    # ── Boolean Accessors ─────────────────────────────────────────
    # ActiveModel boolean attributes don't auto-generate ?-methods like AR

    def auto_create_tables?
      !!auto_create_tables
    end

    def upsert_enabled?
      !!upsert_enabled
    end

    def metadata_column_types
      normalize_hash_config(super)
    end

    def metadata_column_types=(value)
      super(normalize_hash_config(value))
    end

    def metadata_field_mappings
      normalize_hash_config(super)
    end

    def metadata_field_mappings=(value)
      super(normalize_hash_config(value))
    end

    # ── Execution ─────────────────────────────────────────────────

    def execute(documents, context)
      Rag::SqlDatabaseStorageExecutor.new(self, context).call(documents)
    end

    def existing_content_hashes(hashes)
      Rag::SqlDatabaseStorageExecutor.new(self).fetch_existing_content_hashes(hashes)
    end

    def deduplication_applicable?
      pre_load_action == "none"
    end

    def validate_configuration!
      raise "Connector is required" if connector.blank?
      raise "Documents table is required" if documents_table.blank?
      raise "Chunks table is required" if chunks_table.blank?
    end

    def form_partial_path
      FORM_PARTIAL_PATH
    end

    def summary
      action = PRE_LOAD_ACTION_LABELS[pre_load_action] || pre_load_action
      "#{connector&.name || "unknown"} / #{chunks_table} (#{action})"
    end

    def pre_load_action_label
      PRE_LOAD_ACTION_LABELS[pre_load_action] || pre_load_action.titleize
    end

    private

    def connector_must_be_sql_database
      return if connector_id.blank?

      conn = connector
      return errors.add(:connector_id, "connector not found") if conn.nil?
      return if conn.connector_type == "sql_database"

      errors.add(:connector_id, "must be an SQL Database connector")
    end

    def connector_must_support_postgresql_rag_storage
      return if connector.blank?
      return if connector.connector_type != "sql_database"
      return if connector.adapter_type == "postgresql"

      errors.add(:connector_id, "only PostgreSQL connectors are supported for rag storage")
    end

    def metadata_column_types_must_be_valid
      return if metadata_column_types.blank?

      metadata_column_types.each_value do |sql_type|
        next if ALLOWED_COLUMN_TYPES.include?(sql_type.to_s.downcase)

        errors.add(:metadata_column_types, "contains an unsupported SQL type: #{sql_type}")
      end
    end

    def normalize_hash_config(value)
      return {} if value.blank?
      return value.to_h if hash_like_config?(value)
      return parse_hash_config(value) if value.is_a?(String)

      {}
    end

    def hash_like_config?(value)
      value.is_a?(Hash) || (value.respond_to?(:to_h) && !value.is_a?(String))
    end

    def parse_hash_config(value)
      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? parsed : {}
    rescue StandardError
      {}
    end
  end
end
