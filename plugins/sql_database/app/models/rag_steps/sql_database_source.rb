# frozen_string_literal: true

module RagSteps
  # Reads documents from a PostgreSQL database via SQL query.
  # Supports cursor-based batch loading to avoid memory explosion on large datasets.
  class SqlDatabaseSource
    include UndercoverAgents::PluginSystem::Configurator
    include RagStepPlugin
    include SqlDatabaseSourceWizard

    MAX_BATCH_SIZE = 50_000
    MAX_RECORD_LIMIT = 1_000_000
    SOURCE_MODES = ["table", "query"].freeze
    SOURCE_OBJECT_TYPES = ["table", "view", "materialized_view"].freeze
    FORM_PARTIAL_PATH = File.expand_path("../../views/sql_database_source", __dir__).freeze

    attribute :connector_id, :integer
    attribute :source_mode, :string
    attribute :selected_object_name, :string
    attribute :selected_object_type, :string
    attribute :query, :string
    attribute :content_column, :string
    attribute :metadata_columns, default: -> { [] }
    attribute :batch_size, :integer, default: 1000
    attribute :record_limit, :integer
    attribute :incremental_column, :string
    attribute :last_incremental_value, :string

    validates :query, presence: true, unless: :table_mode?
    validates :query, length: { maximum: 10_000 }, allow_blank: true
    validates :content_column, presence: true, length: { maximum: 200 }
    validates :batch_size, presence: true,
                           numericality: { only_integer: true, greater_than: 0,
                                           less_than_or_equal_to: MAX_BATCH_SIZE, }
    validates :record_limit,
              numericality: { only_integer: true, greater_than: 0,
                              less_than_or_equal_to: MAX_RECORD_LIMIT, },
              allow_blank: true
    validates :source_mode, inclusion: { in: SOURCE_MODES }, allow_blank: true
    validates :selected_object_name, presence: true, if: :table_mode?
    validates :selected_object_type, inclusion: { in: SOURCE_OBJECT_TYPES }, allow_blank: true
    validate :connector_must_be_sql_database
    validate :connector_must_support_postgresql_rag_sources
    validate :table_source_must_exist, if: :table_mode?
    validate :query_source_must_be_valid, if: :query_mode?
    before_validation :normalize_wizard_state
    before_validation :build_query_for_selected_object, if: :table_mode?

    # ── Step Type Protocol ────────────────────────────────────────

    key "sql_database_source"
    label "SQL Database"
    icon "fa-solid fa-database"
    stage :source
    description [
      "Ingest documents from a PostgreSQL database using SQL queries.",
      "Supports cursor-based batch loading for large datasets.",
    ].join(" ")

    def self.permitted_params(params)
      params.require(:sql_database_source).permit(
        :connector_id, :source_mode, :selected_object_name, :selected_object_type,
        :query, :content_column, :incremental_column, :batch_size, :record_limit,
        metadata_columns: [],
      )
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    # ── Attribute Overrides ───────────────────────────────────────

    def metadata_columns=(value)
      columns = Array(value)
                .flat_map { |entry| entry.is_a?(String) ? entry.split(",") : entry }
                .filter_map do |entry|
                  name = entry.is_a?(Hash) ? (entry["name"] || entry[:name]) : entry
                  normalized = name.to_s.strip
                  normalized.presence
                end
                .uniq
      super(columns)
    end

    def connector_id=(value)
      remove_instance_variable(:@connector) if defined?(@connector)
      super
    end

    # ── Connector Helper ──────────────────────────────────────────

    def connector
      return @connector if defined?(@connector)

      @connector = find_connector(connector_id)
    end

    def table_mode?
      source_mode == "table"
    end

    def query_mode?
      source_mode == "query"
    end

    # ── Execution ─────────────────────────────────────────────────

    def execute(_documents, context)
      Rag::SqlDatabaseSourceExecutor.new(self, context).call
    end

    def each_batch(context, &)
      Rag::SqlDatabaseSourceExecutor.new(self, context).each_batch(&)
    end

    def validate_configuration!
      raise "Connector is required" if connector.blank?
      raise "Query is required" if query.blank?
      raise "Content column is required" if content_column.blank?
    end

    def form_partial_path
      FORM_PARTIAL_PATH
    end

    def summary
      table_hint = selected_object_name.presence ||
                   query.to_s.match(/FROM\s+(\S+)/i)&.captures&.first ||
                   "custom query"
      "SQL Database — #{connector&.name || "unknown"} (#{table_hint})"
    end

    private

    def connector_must_be_sql_database
      return if connector_id.blank?

      conn = connector
      return errors.add(:connector_id, "connector not found") if conn.nil?
      return if conn.connector_type == "sql_database"

      errors.add(:connector_id, "must be an SQL Database connector")
    end

    def connector_must_support_postgresql_rag_sources
      return if connector.blank?
      return if connector.connector_type != "sql_database"
      return if connector.adapter_type == "postgresql"

      errors.add(:connector_id, "only PostgreSQL connectors are supported for rag sources")
    end
  end
end
