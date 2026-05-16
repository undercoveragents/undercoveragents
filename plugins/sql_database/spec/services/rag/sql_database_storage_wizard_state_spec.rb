# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseStorageWizardState do
  def storage_result(success:, message:, **attributes)
    Rag::SqlDatabaseStorageInspector::Result.new(
      success?: success,
      message:,
      objects: attributes.fetch(:objects, []),
      document_columns: attributes.fetch(:document_columns, []),
      chunk_columns: attributes.fetch(:chunk_columns, []),
      issues: attributes.fetch(:issues, []),
    )
  end

  describe "#storage_mode" do
    it "defaults to new mode when auto-create is already enabled" do
      state = described_class.new(build(:rag_steps_sql_database_storage, storage_mode: nil, auto_create_tables: true))

      expect(state.storage_mode).to eq("new")
    end

    it "defaults to existing mode when auto-create is disabled" do
      state = described_class.new(build(:rag_steps_sql_database_storage, storage_mode: nil, auto_create_tables: false))

      expect(state.storage_mode).to eq("existing")
    end
  end

  describe "#status" do
    it "returns an informational status when no connector is selected" do
      state = described_class.new(build(:rag_steps_sql_database_storage, connector_id: nil))

      expect(state.status).to have_attributes(
        kind: "info",
        message: "Choose a PostgreSQL connector to inspect storage tables or define a new schema.",
      )
    end

    it "returns an informational status in new-table mode" do
      connector = create(:connector, :sql_database, :enabled)
      steppable = build(:rag_steps_sql_database_storage, connector_id: connector.id, storage_mode: "new")
      state = described_class.new(steppable)
      expected_message = "New mode creates the configured documents and chunks tables on first run if needed. " \
                         "It also ensures the documents table has content_hash and configured metadata columns."

      expect(state.status).to have_attributes(
        kind: "info",
        message: expected_message,
      )
    end
  end

  describe "existing-table previews" do
    let(:connector) { create(:connector, :sql_database, :enabled) }
    let(:steppable) do
      build(
        :rag_steps_sql_database_storage,
        connector_id: connector.id,
        storage_mode: "existing",
        documents_table: "documents",
        chunks_table: "chunks",
        content_field: "content",
        embedding_field: "embedding",
        document_reference_field: "document_id",
      )
    end
    let(:inspector) { instance_double(Rag::SqlDatabaseStorageInspector) }
    let(:expected_table_options) do
      [["documents - 2 columns", "documents"], ["chunks - 4 columns", "chunks"]]
    end
    let(:expected_chunk_field_options) do
      [
        ["content - text", "content"],
        ["embedding - vector", "embedding"],
        ["document_id - uuid", "document_id"],
        ["legacy_text", "legacy_text"],
      ]
    end
    let(:objects) do
      [
        {
          "name" => "documents",
          "type" => "table",
          "columns" => [{ "name" => "id", "type" => "uuid" }, { "name" => "content_hash", "type" => "text" }],
        },
        {
          "name" => "chunks",
          "type" => "table",
          "columns" => [
            { "name" => "content", "type" => "text" },
            { "name" => "embedding", "type" => "vector" },
            { "name" => "document_id", "type" => "uuid" },
            { "name" => "legacy_text" },
          ],
        },
      ]
    end

    before do
      allow(Rag::SqlDatabaseStorageInspector).to receive(:new).with(connector).and_return(inspector)
    end

    it "returns table and field options plus a success status" do
      allow(inspector).to receive_messages(
        schema_options: storage_result(success: true, message: "Loaded 2 storage table(s).", objects:),
        validate_existing_tables: storage_result(
          success: true,
          message: "Existing storage schema is ready: documents + chunks.",
          objects:,
        ),
      )

      state = described_class.new(steppable)

      expect(state.table_options).to eq(expected_table_options)
      expect(state.chunk_field_options).to eq(expected_chunk_field_options)
      expect(state.status).to have_attributes(
        kind: "success",
        message: "Existing storage schema is ready: documents + chunks.",
      )
    end

    it "reports schema discovery failures" do
      allow(inspector).to receive(:schema_options).and_return(
        storage_result(success: false, message: "Discovery failed"),
      )

      state = described_class.new(steppable)

      expect(state.status).to have_attributes(kind: "error", message: "Discovery failed")
      expect(state.table_options).to eq([])
      expect(state.chunk_field_options).to eq([])
    end

    it "reports duplicate table selections before validation" do
      allow(inspector).to receive(:schema_options).and_return(
        storage_result(success: true, message: "Loaded 1 storage table(s).", objects:),
      )

      state = described_class.new(steppable.tap { |storage| storage.chunks_table = "documents" })

      expect(state.status).to have_attributes(kind: "error", message: "Documents and chunks tables must be different.")
    end

    it "reports when required field selections are still missing" do
      allow(inspector).to receive(:schema_options).and_return(
        storage_result(success: true, message: "Loaded 2 storage table(s).", objects:),
      )

      state = described_class.new(steppable.tap { |storage| storage.content_field = nil })

      expect(state.status).to have_attributes(
        kind: "info",
        message: "Choose the content, embedding, and document reference columns to validate the existing schema.",
      )
    end

    it "reports validation errors once all fields are selected" do
      allow(inspector).to receive_messages(
        schema_options: storage_result(success: true, message: "Loaded 2 storage table(s).", objects:),
        validate_existing_tables: storage_result(success: false, message: "Embedding column is missing"),
      )

      state = described_class.new(steppable)

      expect(state.status).to have_attributes(kind: "error", message: "Embedding column is missing")
    end

    it "reports when the tables have not been selected yet" do
      allow(inspector).to receive(:schema_options).and_return(
        storage_result(success: true, message: "Loaded 2 storage table(s).", objects:),
      )

      state = described_class.new(
        steppable.tap do |storage|
          storage.documents_table = nil
          storage.chunks_table = nil
        end,
      )

      expect(state.status).to have_attributes(
        kind: "info",
        message: "Choose both the documents table and the chunks table to inspect the available columns.",
      )
    end
  end
end
