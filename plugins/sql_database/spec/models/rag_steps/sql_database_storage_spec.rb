# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSteps::SqlDatabaseStorage do
  describe "validations" do
    subject { build(:rag_steps_sql_database_storage) }

    it { is_expected.to validate_presence_of(:documents_table) }
    it { is_expected.to validate_presence_of(:chunks_table) }
    it { is_expected.to validate_presence_of(:content_field) }
    it { is_expected.to validate_presence_of(:embedding_field) }
    it { is_expected.to validate_presence_of(:document_reference_field) }
    it { is_expected.to validate_presence_of(:pre_load_action) }

    describe "connector_must_be_sql_database" do
      it "is valid with an SQL Database connector" do
        connector = create(:connector, :sql_database, :enabled)
        storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
        expect(storage).to be_valid
      end

      it "is invalid with an LLM Provider connector" do
        llm_connector = create(:connector, :llm_provider)
        storage = build(:rag_steps_sql_database_storage, connector_id: llm_connector.id)
        expect(storage).not_to be_valid
        expect(storage.errors[:connector_id]).to include("must be an SQL Database connector")
      end

      it "skips validation when connector_id is blank" do
        storage = build(:rag_steps_sql_database_storage, connector_id: nil)
        storage.valid?
        expect(storage.errors[:connector_id]).not_to include("must be an SQL Database connector")
      end

      it "adds error when connector is not found" do
        storage = build(:rag_steps_sql_database_storage, connector_id: 999_999)
        expect(storage).not_to be_valid
        expect(storage.errors[:connector_id]).to include("connector not found")
      end

      it "rejects non-postgresql SQL connectors" do
        connector = create(:connector, :sql_database, adapter_type: "mysql")
        storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)

        expect(storage).not_to be_valid
        expect(storage.errors[:connector_id]).to include("only PostgreSQL connectors are supported for rag storage")
      end
    end

    describe "metadata_column_types_must_be_valid" do
      it "rejects unsupported SQL types" do
        storage = build(:rag_steps_sql_database_storage, metadata_column_types: { "col" => "blob" })
        expect(storage).not_to be_valid
        expect(storage.errors[:metadata_column_types]).to be_present
      end

      it "accepts supported SQL types" do
        storage = build(:rag_steps_sql_database_storage,
                        metadata_column_types: { "col" => "text", "num" => "integer" },)
        expect(storage).to be_valid
      end

      it "coerces JSON-string configs into hashes" do
        storage = build(
          :rag_steps_sql_database_storage,
          metadata_column_types: "{\"source\":\"text\"}",
          metadata_field_mappings: "{\"author\":\"author_col\"}",
        )

        expect(storage.metadata_column_types).to eq({ "source" => "text" })
        expect(storage.metadata_field_mappings).to eq({ "author" => "author_col" })
        expect(storage).to be_valid
      end
    end
  end

  describe ".key" do
    it { expect(described_class.key).to eq("sql_database_storage") }
  end

  describe ".label" do
    it { expect(described_class.label).to eq("SQL Database") }
  end

  describe ".stage" do
    it { expect(described_class.stage).to eq(:storage) }
  end

  describe ".build_from_params" do
    it "builds a new instance from params" do
      connector = create(:connector, :sql_database, :enabled)
      params = ActionController::Parameters.new(
        sql_database_storage: {
          connector_id: connector.id,
          storage_mode: "new",
          documents_table: "docs",
          chunks_table: "chunks",
          content_field: "content",
          embedding_field: "embedding",
          document_reference_field: "doc_id",
          pre_load_action: "none",
        },
      )
      storage = described_class.build_from_params(params)
      expect(storage).to be_a(described_class)
      expect(storage.storage_mode).to eq("new")
      expect(storage.documents_table).to eq("docs")
    end
  end

  describe "#validate_configuration!" do
    it "raises when connector is blank" do
      storage = build(:rag_steps_sql_database_storage, connector_id: nil)
      expect { storage.validate_configuration! }.to raise_error("Connector is required")
    end

    it "raises when documents_table is blank" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id, documents_table: nil)
      expect { storage.validate_configuration! }.to raise_error("Documents table is required")
    end

    it "raises when chunks_table is blank" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id, chunks_table: nil)
      expect { storage.validate_configuration! }.to raise_error("Chunks table is required")
    end

    it "does not raise when fully configured" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
      expect { storage.validate_configuration! }.not_to raise_error
    end
  end

  describe "#summary" do
    it "includes connector name and tables" do
      connector = create(:connector, :sql_database, :enabled, name: "My DB")
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id,
                                                       documents_table: "docs",
                                                       chunks_table: "chunks",)
      expect(storage.summary).to eq("My DB / chunks (None (append))")
    end

    it "uses 'unknown' when connector is nil" do
      storage = build(:rag_steps_sql_database_storage, connector_id: nil)
      expect(storage.summary).to include("unknown")
    end
  end

  describe "#execute" do
    it "delegates to SqlDatabaseStorageExecutor" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
      docs = []
      allow(Rag::SqlDatabaseStorageExecutor).to receive(:new).and_call_original
      allow_any_instance_of(Rag::SqlDatabaseStorageExecutor).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance
      storage.execute(docs, {})
      expect(Rag::SqlDatabaseStorageExecutor).to have_received(:new).with(storage, {})
    end
  end

  describe "#pre_load_action_label" do
    it 'returns "None (append)" for none' do
      storage = build(:rag_steps_sql_database_storage, pre_load_action: "none")
      expect(storage.pre_load_action_label).to eq("None (append)")
    end

    it 'returns "Truncate tables" for truncate' do
      storage = build(:rag_steps_sql_database_storage, pre_load_action: "truncate")
      expect(storage.pre_load_action_label).to eq("Truncate tables")
    end
  end

  describe "constants" do
    it "defines PRE_LOAD_ACTIONS" do
      expect(described_class::PRE_LOAD_ACTIONS).to include("none", "truncate", "delete_matching")
    end
  end

  describe ".icon" do
    it { expect(described_class.icon).to eq("fa-solid fa-hard-drive") }
  end

  describe ".description" do
    it "returns a non-empty description" do
      expect(described_class.description).to include("PostgreSQL database")
    end
  end

  describe ".permitted_params" do
    it "returns sql_database_storage params" do
      params = ActionController::Parameters.new(
        sql_database_storage: {
          connector_id: "1", storage_mode: "existing", documents_table: "docs", chunks_table: "chunks",
          content_field: "content", embedding_field: "embedding",
          document_reference_field: "doc_id", pre_load_action: "none",
          upsert_enabled: "true", auto_create_tables: "true", embedding_dimensions: "1536",
          metadata_field_mappings: { "a" => "b" }, metadata_column_types: { "c" => "text" },
        },
      )
      result = described_class.permitted_params(params)
      expect(result[:storage_mode]).to eq("existing")
      expect(result[:documents_table]).to eq("docs")
      expect(result[:upsert_enabled]).to eq("true")
    end
  end

  describe "wizard state" do
    let(:invalid_existing_schema_result) do
      Rag::SqlDatabaseStorageInspector::Result.new(
        success?: false,
        message: "Invalid schema",
        objects: [],
        document_columns: [],
        chunk_columns: [],
        issues: [{ field: :documents_table, message: "must include an 'id' column" }],
      )
    end
    let(:valid_existing_schema_result) do
      Rag::SqlDatabaseStorageInspector::Result.new(
        success?: true,
        message: "Existing storage schema is ready",
        objects: [],
        document_columns: ["id", "content_hash"],
        chunk_columns: ["content", "embedding", "document_id"],
        issues: [],
      )
    end
    let(:existing_connector) { create(:connector, :sql_database, :enabled) }
    let(:existing_storage) do
      build(
        :rag_steps_sql_database_storage,
        connector_id: existing_connector.id,
        storage_mode: "existing",
        documents_table: "documents",
        chunks_table: "chunks",
      )
    end
    let(:existing_storage_inspector) { instance_double(Rag::SqlDatabaseStorageInspector) }
    let(:inspection_failure_result) do
      Rag::SqlDatabaseStorageInspector::Result.new(
        success?: false,
        message: "Storage unavailable",
        objects: [],
        document_columns: [],
        chunk_columns: [],
        issues: [],
      )
    end

    it "syncs auto_create_tables when storage_mode is new" do
      storage = build(:rag_steps_sql_database_storage, storage_mode: "new", auto_create_tables: false)

      storage.valid?

      expect(storage.auto_create_tables?).to be(true)
    end

    it "requires different documents and chunks tables" do
      storage = build(
        :rag_steps_sql_database_storage,
        storage_mode: "new",
        documents_table: "shared_table",
        chunks_table: "shared_table",
      )

      expect(storage).not_to be_valid
      expect(storage.errors[:chunks_table]).to include("must be different from documents table")
    end

    it "adds schema validation errors in existing mode" do
      allow(Rag::SqlDatabaseStorageInspector).to receive(:new)
        .with(existing_connector)
        .and_return(existing_storage_inspector)
      allow(existing_storage_inspector).to receive(:validate_existing_tables).and_return(invalid_existing_schema_result)

      expect(existing_storage).not_to be_valid
      expect(existing_storage.errors[:documents_table]).to include("must include an 'id' column")
    end

    it "adds a base error when schema inspection fails without field-level issues" do
      allow(Rag::SqlDatabaseStorageInspector).to receive(:new)
        .with(existing_connector)
        .and_return(existing_storage_inspector)
      allow(existing_storage_inspector).to receive(:validate_existing_tables).and_return(inspection_failure_result)

      expect(existing_storage).not_to be_valid
      expect(existing_storage.errors[:base]).to include("Storage unavailable")
    end

    it "accepts existing mode when the inspected schema is valid" do
      inspector = instance_double(
        Rag::SqlDatabaseStorageInspector,
        validate_existing_tables: valid_existing_schema_result,
      )

      allow(Rag::SqlDatabaseStorageInspector).to receive(:new).with(existing_connector).and_return(inspector)

      expect(existing_storage).to be_valid
    end

    it "skips schema inspection when required fields already failed validation" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(
        :rag_steps_sql_database_storage,
        connector_id: connector.id,
        storage_mode: "existing",
        documents_table: nil,
        chunks_table: "chunks",
      )

      allow(Rag::SqlDatabaseStorageInspector).to receive(:new)

      expect(storage).not_to be_valid
      expect(Rag::SqlDatabaseStorageInspector).not_to have_received(:new)
      expect(storage.errors[:documents_table]).to include("can't be blank")
    end
  end

  describe "#form_partial_path" do
    it "returns the expected partial path" do
      storage = build(:rag_steps_sql_database_storage)
      expect(File.directory?(storage.form_partial_path)).to be(true)
      expect(File.exist?(File.join(storage.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#connector" do
    it "returns the connector when connector_id is set" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
      expect(storage.connector).to eq(connector)
    end

    it "returns nil when connector_id is nil" do
      storage = build(:rag_steps_sql_database_storage, connector_id: nil)
      expect(storage.connector).to be_nil
    end
  end

  describe "#auto_create_tables?" do
    it "returns false when auto_create_tables is false" do
      storage = build(:rag_steps_sql_database_storage, auto_create_tables: false)
      expect(storage.auto_create_tables?).to be(false)
    end

    it "returns true when auto_create_tables is true" do
      storage = build(:rag_steps_sql_database_storage, auto_create_tables: true)
      expect(storage.auto_create_tables?).to be(true)
    end
  end

  describe "#upsert_enabled?" do
    it "returns false when upsert_enabled is false" do
      storage = build(:rag_steps_sql_database_storage, upsert_enabled: false)
      expect(storage.upsert_enabled?).to be(false)
    end

    it "returns true when upsert_enabled is true" do
      storage = build(:rag_steps_sql_database_storage, upsert_enabled: true)
      expect(storage.upsert_enabled?).to be(true)
    end
  end

  describe "#deduplication_applicable?" do
    it 'returns true when pre_load_action is "none"' do
      storage = build(:rag_steps_sql_database_storage, pre_load_action: "none")
      expect(storage.deduplication_applicable?).to be(true)
    end

    it 'returns false when pre_load_action is "truncate"' do
      storage = build(:rag_steps_sql_database_storage, pre_load_action: "truncate")
      expect(storage.deduplication_applicable?).to be(false)
    end
  end

  describe "#existing_content_hashes" do
    it "delegates to SqlDatabaseStorageExecutor" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
      executor = instance_double(Rag::SqlDatabaseStorageExecutor)
      allow(Rag::SqlDatabaseStorageExecutor).to receive(:new).and_return(executor)
      allow(executor).to receive(:fetch_existing_content_hashes).and_return(Set.new)
      storage.existing_content_hashes(["abc"])
      expect(executor).to have_received(:fetch_existing_content_hashes).with(["abc"])
    end
  end

  describe "normalize_hash_config" do
    it "returns empty hash for nil" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: nil)
      expect(storage.metadata_column_types).to eq({})
    end

    it "returns empty hash for non-JSON string" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: "not json")
      expect(storage.metadata_column_types).to eq({})
    end

    it "returns empty hash for non-hash types" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: 42)
      expect(storage.metadata_column_types).to eq({})
    end

    it "returns empty hash for JSON string that parses to non-hash (e.g. array)" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: "[1, 2, 3]")
      expect(storage.metadata_column_types).to eq({})
    end

    it "returns empty hash for JSON string that parses to integer" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: "42")
      expect(storage.metadata_column_types).to eq({})
    end

    it "returns hash when JSON string parses to hash" do
      storage = build(:rag_steps_sql_database_storage, metadata_column_types: '{"col": "text"}')
      expect(storage.metadata_column_types).to eq({ "col" => "text" })
    end

    it "normalizes metadata_field_mappings the same way" do
      storage = build(:rag_steps_sql_database_storage, metadata_field_mappings: "[1, 2]")
      expect(storage.metadata_field_mappings).to eq({})
    end
  end

  describe "#to_configuration" do
    it "returns a serializable hash" do
      connector = create(:connector, :sql_database, :enabled)
      storage = build(:rag_steps_sql_database_storage, connector_id: connector.id)
      config = storage.to_configuration
      expect(config).to include("connector_id" => connector.id, "documents_table" => "documents")
    end
  end
end
