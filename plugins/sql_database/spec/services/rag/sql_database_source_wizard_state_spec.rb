# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseSourceWizardState do
  def source_result(success:, message:, objects: [], columns: [])
    Rag::SqlDatabaseSourceInspector::Result.new(success?: success, message:, objects:, columns:)
  end

  describe "#source_mode" do
    it "defaults to table mode when no explicit source is configured" do
      state = described_class.new(build(:rag_steps_sql_database_source, source_mode: nil, query: nil))

      expect(state.source_mode).to eq("table")
    end

    it "infers table mode from a selected object" do
      state = described_class.new(build(:rag_steps_sql_database_source, source_mode: nil, selected_object_name: "docs"))

      expect(state.source_mode).to eq("table")
    end

    it "infers query mode from a saved query" do
      source = build(:rag_steps_sql_database_source, source_mode: nil, query: "SELECT body FROM docs")
      state = described_class.new(source)

      expect(state.source_mode).to eq("query")
    end
  end

  describe "table previews" do
    let(:connector) { create(:connector, :sql_database, :enabled) }
    let(:expected_query) do
      'SELECT "plain_text", "title", "updated_at" FROM "public"."kb_documents" LIMIT 25'
    end
    let(:steppable) do
      build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "table",
        selected_object_name: "kb_documents",
        content_column: "plain_text",
        metadata_columns: ["title"],
        incremental_column: "updated_at",
        record_limit: 25,
      )
    end
    let(:inspector) { instance_double(Rag::SqlDatabaseSourceInspector) }

    before do
      allow(Rag::SqlDatabaseSourceInspector).to receive(:new).with(connector).and_return(inspector)
      allow(inspector).to receive(:schema_options).and_return(
        source_result(
          success: true,
          message: "Loaded 1 source object(s).",
          objects: [{
            "name" => "kb_documents",
            "type" => "materialized_view",
            "columns" => [
              { "name" => "plain_text", "type" => "text" },
              { "name" => "title", "type" => "text" },
              { "name" => "updated_at", "type" => "timestamp" },
            ],
          }],
        ),
      )
    end

    it "builds object options and status from the schema" do
      state = described_class.new(steppable)

      expect(state.object_options).to eq([["kb_documents - materialized view", "kb_documents"]])
      expect(state.column_options).to eq(
        [
          ["plain_text - text", "plain_text"],
          ["title - text", "title"],
          ["updated_at - timestamp", "updated_at"],
        ],
      )
      expect(state.selected_object_type).to eq("materialized_view")
      expect(state.status).to have_attributes(kind: "success", message: "Loaded 3 columns from kb_documents.")
    end

    it "builds the generated query preview" do
      state = described_class.new(steppable)

      expect(state.query_value).to eq(expected_query)
    end

    it "reports schema failures in table mode" do
      allow(inspector).to receive(:schema_options).and_return(
        source_result(success: false, message: "Connection timed out"),
      )

      state = described_class.new(steppable)

      expect(state.status).to have_attributes(kind: "error", message: "Connection timed out")
      expect(state.object_options).to eq([])
      expect(state.column_options).to eq([])
    end

    it "returns an informational status until a table is selected" do
      state = described_class.new(steppable.tap { |source| source.selected_object_name = nil })

      expect(state.status).to have_attributes(
        kind: "info",
        message: "Choose a table or view to load its available columns.",
      )
    end
  end

  describe "query previews" do
    let(:connector) { create(:connector, :sql_database, :enabled) }
    let(:steppable) do
      build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT body, title FROM docs",
      )
    end
    let(:inspector) { instance_double(Rag::SqlDatabaseSourceInspector) }

    before do
      allow(Rag::SqlDatabaseSourceInspector).to receive(:new).with(connector).and_return(inspector)
    end

    it "returns query columns and a success status" do
      allow(inspector).to receive(:validate_query).with("SELECT body, title FROM docs").and_return(
        source_result(success: true, message: "Query is valid! Found 2 column(s).", columns: ["body", "title"]),
      )

      state = described_class.new(steppable)

      expect(state.column_options).to eq([["body", "body"], ["title", "title"]])
      expect(state.status).to have_attributes(kind: "success", message: "Query is valid! Found 2 column(s).")
    end

    it "reports query inspection failures" do
      allow(inspector).to receive(:validate_query).with("SELECT body, title FROM docs").and_return(
        source_result(success: false, message: "Syntax error near FROM"),
      )

      state = described_class.new(steppable)

      expect(state.column_options).to eq([])
      expect(state.status).to have_attributes(kind: "error", message: "Syntax error near FROM")
    end

    it "returns an informational status until the query is filled in" do
      state = described_class.new(steppable.tap { |source| source.query = nil })

      expect(state.status).to have_attributes(
        kind: "info",
        message: "Write a read-only SELECT query, then analyze it to load its result columns.",
      )
    end
  end
end
