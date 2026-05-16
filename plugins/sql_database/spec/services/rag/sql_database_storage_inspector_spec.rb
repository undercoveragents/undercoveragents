# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseStorageInspector do
  describe "#schema_options" do
    it "returns an error when no connector is selected" do
      result = described_class.new(nil).schema_options

      expect(result).to have_attributes(success?: false, message: "No connector selected.")
    end

    it "returns an error when the connector is not a SQL database" do
      connector = create(:connector, :llm_provider, :enabled)

      result = described_class.new(connector).schema_options

      expect(result).to have_attributes(success?: false, message: "Connector must be a SQL Database.")
    end

    it "returns an error when the connector is not PostgreSQL" do
      connector = create(:connector, :sql_database, :enabled, adapter_type: "mysql")

      result = described_class.new(connector).schema_options

      expect(result).to have_attributes(success?: false, message: "Only PostgreSQL is supported.")
    end

    it "returns a failure when schema discovery reports an error" do
      connector = create(:connector, :sql_database, :enabled)
      discoverer = instance_double(Tools::SchemaDiscoverer)
      result = instance_double(Tools::SchemaDiscoverer::Result, success?: false, message: "Discovery failed")
      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_return(discoverer)
      allow(discoverer).to receive(:call).and_return(result)

      response = described_class.new(connector).schema_options

      expect(response).not_to be_success
      expect(response.message).to eq("Discovery failed")
    end

    it "returns a rescued error when schema discovery raises" do
      connector = create(:connector, :sql_database, :enabled)
      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_raise(StandardError, "boom")

      response = described_class.new(connector).schema_options

      expect(response).not_to be_success
      expect(response.message).to eq("Error: boom")
    end

    it "returns an empty object list when discovery has no schema payload" do
      connector = create(:connector, :sql_database, :enabled)
      discoverer = instance_double(Tools::SchemaDiscoverer)
      result = instance_double(Tools::SchemaDiscoverer::Result, success?: true, message: "ok", schema: nil)
      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_return(discoverer)
      allow(discoverer).to receive(:call).and_return(result)

      response = described_class.new(connector).schema_options

      expect(response).to be_success
      expect(response.objects).to eq([])
    end

    it "filters the discovered schema down to tables" do
      connector = create(:connector, :sql_database, :enabled)
      discoverer = instance_double(Tools::SchemaDiscoverer)
      result = instance_double(
        Tools::SchemaDiscoverer::Result,
        success?: true,
        message: "Discovered 3 objects",
        schema: {
          "objects" => [
            { "name" => "documents", "type" => "table", "columns" => [{ "name" => "id", "type" => "uuid" }] },
            { "name" => "chunks", "type" => "table", "columns" => [{ "name" => "content", "type" => "text" }] },
            { "name" => "documents_view", "type" => "view", "columns" => [{ "name" => "id", "type" => "uuid" }] },
          ],
        },
      )
      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_return(discoverer)
      allow(discoverer).to receive(:call).and_return(result)

      response = described_class.new(connector).schema_options

      expect(response).to be_success
      expect(response.objects.pluck("name")).to eq(["documents", "chunks"])
    end
  end

  describe "#validate_existing_tables" do
    let(:connector) { create(:connector, :sql_database, :enabled) }
    let(:inspector) { described_class.new(connector) }
    let(:schema_options_without_core_document_columns) do
      described_class::Result.new(
        success?: true,
        message: "Loaded tables",
        objects: [
          {
            "name" => "documents",
            "type" => "table",
            "columns" => [{ "name" => "author", "type" => "text" }],
          },
          {
            "name" => "chunks",
            "type" => "table",
            "columns" => [
              { "name" => "document_id", "type" => "uuid" },
              { "name" => "content", "type" => "text" },
              { "name" => "embedding", "type" => "vector" },
            ],
          },
        ],
        document_columns: [],
        chunk_columns: [],
        issues: [],
      )
    end

    before do
      allow(inspector).to receive(:schema_options).and_return(
        described_class::Result.new(
          success?: true,
          message: "Loaded tables",
          objects: [
            {
              "name" => "documents",
              "type" => "table",
              "columns" => [
                { "name" => "id", "type" => "uuid" },
                { "name" => "content_hash", "type" => "varchar" },
                { "name" => "author", "type" => "text" },
              ],
            },
            {
              "name" => "chunks",
              "type" => "table",
              "columns" => [
                { "name" => "document_id", "type" => "uuid" },
                { "name" => "content", "type" => "text" },
                { "name" => "embedding", "type" => "vector" },
              ],
            },
          ],
          document_columns: [],
          chunk_columns: [],
          issues: [],
        ),
      )
    end

    it "returns success when the required tables and columns exist" do
      result = inspector.validate_existing_tables(
        documents_table: "documents",
        chunks_table: "chunks",
        content_field: "content",
        embedding_field: "embedding",
        document_reference_field: "document_id",
        metadata_field_mappings: { "author" => "author" },
      )

      expect(result).to be_success
      expect(result.message).to include("Existing storage schema is ready")
    end

    it "returns issues when the schema is missing required columns" do
      result = inspector.validate_existing_tables(
        documents_table: "documents",
        chunks_table: "chunks",
        content_field: "body",
        embedding_field: "embedding",
        document_reference_field: "missing_document_id",
        metadata_field_mappings: { "source" => "source_col" },
      )

      expect(result).not_to be_success
      expect(result.issues).to include(include(field: :content_field))
      expect(result.issues).to include(include(field: :document_reference_field))
      expect(result.issues).to include(
        include(field: :documents_table, message: "must include metadata column 'source_col'"),
      )
    end

    it "returns schema failures directly when schema options are unavailable" do
      failure_result = described_class::Result.new(
        success?: false,
        message: "Only PostgreSQL is supported.",
        objects: [],
        document_columns: [],
        chunk_columns: [],
        issues: [],
      )
      allow(inspector).to receive(:schema_options).and_return(failure_result)

      result = inspector.validate_existing_tables(documents_table: "documents", chunks_table: "chunks")

      expect(result).to have_attributes(success?: false, message: "Only PostgreSQL is supported.")
    end

    it "reports missing documents and chunks tables" do
      result = inspector.validate_existing_tables(
        documents_table: "missing_documents",
        chunks_table: "missing_chunks",
        content_field: "content",
        embedding_field: "embedding",
        document_reference_field: "document_id",
      )

      expect(result).not_to be_success
      expect(result.issues).to include(
        include(field: :documents_table, message: "must match an existing table"),
      )
      expect(result.issues).to include(include(field: :chunks_table, message: "must match an existing table"))
      expect(result.document_columns).to eq([])
      expect(result.chunk_columns).to eq([])
    end

    it "reports missing core document columns" do
      allow(inspector).to receive(:schema_options).and_return(schema_options_without_core_document_columns)

      result = inspector.validate_existing_tables(
        documents_table: "documents",
        chunks_table: "chunks",
        content_field: "content",
        embedding_field: "embedding",
        document_reference_field: "document_id",
      )

      expect(result).not_to be_success
      expect(result.issues).to include(include(field: :documents_table, message: "must include an 'id' column"))
      expect(result.issues).to include(
        include(field: :documents_table, message: "must include a 'content_hash' column"),
      )
    end
  end
end
