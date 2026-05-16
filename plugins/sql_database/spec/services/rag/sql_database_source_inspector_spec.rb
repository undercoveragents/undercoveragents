# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseSourceInspector do
  subject(:inspector) { described_class.new(connector) }

  let(:connector) { create(:connector, :sql_database, :enabled) }

  describe "#schema_options" do
    let(:discoverer) { instance_double(Tools::SchemaDiscoverer) }
    let(:discovered_objects) do
      [{
        "name" => "kb_documents",
        "type" => "table",
        "columns" => [
          { "name" => "body", "type" => "text", "nullable" => true },
          { name: "title", type: "text" },
        ],
      }]
    end
    let(:normalized_objects) do
      [
        {
          "name" => "kb_documents",
          "type" => "table",
          "columns" => [
            { "name" => "body", "type" => "text", "nullable" => true },
            { "name" => "title", "type" => "text", "nullable" => false },
          ],
        },
      ]
    end

    before do
      allow(Tools::SchemaDiscoverer).to receive(:new).with(connector).and_return(discoverer)
    end

    it "returns the discoverer failure message" do
      result = instance_double(Tools::SchemaDiscoverer::Result, success?: false, message: "Discovery failed")
      allow(discoverer).to receive(:call).and_return(result)

      response = inspector.schema_options

      expect(response.success?).to be(false)
      expect(response.message).to eq("Discovery failed")
    end

    it "returns an empty object list when the schema payload is missing" do
      result = instance_double(Tools::SchemaDiscoverer::Result, success?: true, schema: nil)
      allow(discoverer).to receive(:call).and_return(result)

      response = inspector.schema_options

      expect(response.success?).to be(true)
      expect(response.objects).to eq([])
    end

    it "normalizes discovered objects and columns" do
      result = instance_double(
        Tools::SchemaDiscoverer::Result,
        success?: true,
        schema: { "objects" => discovered_objects },
      )
      allow(discoverer).to receive(:call).and_return(result)

      response = inspector.schema_options

      expect(response.success?).to be(true)
      expect(response.objects).to eq(normalized_objects)
    end

    it "wraps discovery exceptions in an error response" do
      allow(discoverer).to receive(:call).and_raise(StandardError, "boom")

      response = inspector.schema_options

      expect(response.success?).to be(false)
      expect(response.message).to include("Error:")
    end

    it "rejects non-sql connectors" do
      response = described_class.new(create(:connector, :llm_provider)).schema_options

      expect(response).to have_attributes(success?: false, message: "Connector must be a SQL Database.")
    end

    it "rejects non-postgresql connectors" do
      response = described_class.new(create(:connector, :sql_database, adapter_type: "mysql")).schema_options

      expect(response).to have_attributes(success?: false, message: "Only PostgreSQL is supported.")
    end
  end

  describe "#validate_query" do
    let(:mock_conn) { instance_double(PG::Connection) }
    let(:mock_result) { instance_double(PG::Result, fields: ["body"]) }

    before do
      allow(PG).to receive(:connect).and_return(mock_conn)
      allow(mock_conn).to receive(:close)
      allow(mock_conn).to receive(:exec).with("BEGIN TRANSACTION READ ONLY").and_return(nil)
      allow(mock_conn).to receive(:exec)
        .with("SELECT * FROM (SELECT body FROM docs) _q LIMIT 0")
        .and_return(mock_result)
    end

    it "swallows rollback errors raised during cleanup" do
      rollback_calls = 0
      allow(mock_conn).to receive(:exec).with("ROLLBACK") do
        rollback_calls += 1
        raise StandardError, "rollback failed" if rollback_calls == 2

        nil
      end

      response = inspector.validate_query("SELECT body FROM docs")

      expect(response.success?).to be(true)
      expect(response.columns).to eq(["body"])
      expect(mock_conn).to have_received(:close)
    end

    it "returns the connector error when no connector is selected" do
      response = described_class.new(nil).validate_query("SELECT body FROM docs")

      expect(response).to have_attributes(success?: false, message: "No connector selected.")
    end

    it "returns an error when the query is blank" do
      response = inspector.validate_query("   ")

      expect(response).to have_attributes(success?: false, message: "No SQL query entered.")
    end

    it "returns an error when query inspection raises" do
      allow(PG).to receive(:connect).and_raise(StandardError, "boom")

      response = inspector.validate_query("SELECT body FROM docs")

      expect(response.success?).to be(false)
      expect(response.message).to eq("Error: boom")
    end
  end
end
