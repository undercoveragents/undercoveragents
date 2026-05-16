# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagSteps::SqlDatabaseSource do
  def inspector_result(success:, message: "ok", objects: [], columns: [])
    Rag::SqlDatabaseSourceInspector::Result.new(success?: success, message:, objects:, columns:)
  end

  def table_schema_result(object_name, columns)
    inspector_result(
      success: true,
      objects: [{
        "name" => object_name,
        "type" => "table",
        "columns" => columns.map { |column| { "name" => column } },
      }],
    )
  end

  describe "validations" do
    subject(:source) { build(:rag_steps_sql_database_source) }

    it { is_expected.to validate_presence_of(:content_column) }
    it { is_expected.to validate_presence_of(:batch_size) }
    it { is_expected.to validate_length_of(:query).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:content_column).is_at_most(200) }

    it "requires a query in query mode" do
      source.source_mode = "query"
      source.query = nil

      source.valid?

      expect(source.errors[:query]).to include("can't be blank")
    end

    it "requires a selected object in table mode" do
      source.source_mode = "table"
      source.selected_object_name = nil

      source.valid?

      expect(source.errors[:selected_object_name]).to include("can't be blank")
    end

    it "rejects unsupported source modes" do
      source.source_mode = "invalid"

      source.valid?

      expect(source.errors[:source_mode]).to include("is not included in the list")
    end

    it "validates batch_size is greater than 0" do
      source.batch_size = 0

      source.valid?

      expect(source.errors[:batch_size]).to include("must be greater than 0")
    end

    it "validates record_limit is greater than 0" do
      source.record_limit = 0

      source.valid?

      expect(source.errors[:record_limit]).to include("must be greater than 0")
    end

    describe "connector_must_be_sql_database" do
      it "is valid with an SQL Database connector" do
        connector = create(:connector, :sql_database, :enabled)
        source = build(:rag_steps_sql_database_source, connector_id: connector.id)

        expect(source).to be_valid
      end

      it "is invalid with an LLM Provider connector" do
        llm_connector = create(:connector, :llm_provider)
        source = build(:rag_steps_sql_database_source, connector_id: llm_connector.id)

        expect(source).not_to be_valid
        expect(source.errors[:connector_id]).to include("must be an SQL Database connector")
      end

      it "skips validation when connector_id is blank" do
        source = build(:rag_steps_sql_database_source, connector_id: nil)
        source.valid?

        expect(source.errors[:connector_id]).not_to include("must be an SQL Database connector")
      end

      it "adds error when connector is not found" do
        source = build(:rag_steps_sql_database_source, connector_id: 999_999)

        expect(source).not_to be_valid
        expect(source.errors[:connector_id]).to include("connector not found")
      end

      it "rejects non-postgresql SQL connectors" do
        connector = create(:connector, :sql_database, adapter_type: "mysql")
        source = build(:rag_steps_sql_database_source, connector_id: connector.id)

        source.valid?

        expect(source.errors[:connector_id]).to include("only PostgreSQL connectors are supported for rag sources")
      end
    end
  end

  describe ".key" do
    it { expect(described_class.key).to eq("sql_database_source") }
  end

  describe ".label" do
    it { expect(described_class.label).to eq("SQL Database") }
  end

  describe ".stage" do
    it { expect(described_class.stage).to eq(:source) }
  end

  describe ".build_from_params" do
    it "builds a new instance from params" do
      connector = create(:connector, :sql_database, :enabled)
      params = ActionController::Parameters.new(
        sql_database_source: {
          connector_id: connector.id,
          source_mode: "query",
          query: "SELECT body FROM t",
          content_column: "body",
          metadata_columns: ["title"],
          record_limit: 25,
          batch_size: 500,
        },
      )

      source = described_class.build_from_params(params)

      expect(source).to be_a(described_class)
      expect(source.query).to eq("SELECT body FROM t")
      expect(source.metadata_columns).to eq(["title"])
      expect(source.record_limit).to eq(25)
    end
  end

  describe "#metadata_columns=" do
    it "splits a comma-separated string into an array" do
      source = described_class.new
      source.metadata_columns = "col1, col2, col3"

      expect(source.metadata_columns).to eq(["col1", "col2", "col3"])
    end

    it "rejects empty entries" do
      source = described_class.new
      source.metadata_columns = ["col1", "", "col2"]

      expect(source.metadata_columns).to eq(["col1", "col2"])
    end

    it "extracts names from hashes" do
      source = described_class.new
      source.metadata_columns = [{ name: "col1" }, { "name" => "col2" }]

      expect(source.metadata_columns).to eq(["col1", "col2"])
    end
  end

  describe "database-backed validations" do
    let(:connector) { create(:connector, :sql_database, :enabled) }
    let(:inspector) { instance_double(Rag::SqlDatabaseSourceInspector) }

    before do
      allow(Rag::SqlDatabaseSourceInspector).to receive(:new).with(connector).and_return(inspector)
    end

    it "validates a custom query through the inspector" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT body, title, updated_at FROM docs",
        content_column: "body",
        metadata_columns: ["title"],
        incremental_column: "updated_at",
      )
      allow(inspector).to receive(:validate_query).and_return(
        inspector_result(success: true, message: "Query is valid!", columns: ["body", "title", "updated_at"]),
      )

      expect(source).to be_valid
    end

    it "adds query errors when the inspector rejects the query" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT body FROM docs",
        content_column: "body",
      )
      allow(inspector).to receive(:validate_query).and_return(
        inspector_result(success: false, message: "Syntax error near FROM"),
      )

      source.valid?

      expect(source.errors[:query]).to include("Syntax error near FROM")
    end

    it "reports missing query output columns" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT body FROM docs",
        content_column: "body",
        metadata_columns: ["title"],
        incremental_column: "updated_at",
      )
      allow(inspector).to receive(:validate_query).and_return(inspector_result(success: true, columns: ["body"]))

      source.valid?

      expect(source.errors[:metadata_columns]).to include("contains 'title', which was not found")
      expect(source.errors[:incremental_column]).to include("was not found in the selected source")
    end

    it "reports a missing content column in query mode" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "query",
        query: "SELECT title FROM docs",
        content_column: "body",
      )
      allow(inspector).to receive(:validate_query).and_return(inspector_result(success: true, columns: ["title"]))

      source.valid?

      expect(source.errors[:content_column]).to include("was not found in the selected source")
    end

    it "builds and validates a table-based query" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "table",
        selected_object_name: "kb_documents",
        content_column: "plain_text",
        metadata_columns: ["title"],
        incremental_column: "updated_at",
        record_limit: 25,
      )
      allow(inspector).to receive(:schema_options).and_return(
        table_schema_result("kb_documents", ["plain_text", "title", "updated_at"]),
      )

      expect(source).to be_valid
      expect(source.query).to eq('SELECT "plain_text", "title", "updated_at" FROM "public"."kb_documents" LIMIT 25')
      expect(source.selected_object_type).to eq("table")
    end

    it "reports missing table columns" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "table",
        selected_object_name: "kb_documents",
        content_column: "plain_text",
        metadata_columns: ["title"],
      )
      allow(inspector).to receive(:schema_options).and_return(table_schema_result("kb_documents", ["plain_text"]))

      source.valid?

      expect(source.errors[:metadata_columns]).to include("contains 'title', which was not found")
    end

    it "adds a base error when schema inspection fails in table mode" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "table",
        selected_object_name: "kb_documents",
        content_column: "plain_text",
      )
      allow(inspector).to receive(:schema_options).and_return(
        inspector_result(success: false, message: "Connection timed out"),
      )

      source.valid?

      expect(source.errors[:base]).to include("Connection timed out")
    end

    it "requires the selected object to exist in table mode" do
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        source_mode: "table",
        selected_object_name: "missing_table",
        content_column: "plain_text",
      )
      allow(inspector).to receive(:schema_options).and_return(inspector_result(success: true, objects: []))

      source.valid?

      expect(source.errors[:selected_object_name]).to include("must match an existing table or view")
    end
  end

  describe "#validate_configuration!" do
    it "raises when connector is blank" do
      source = build(:rag_steps_sql_database_source, connector_id: nil)

      expect { source.validate_configuration! }.to raise_error("Connector is required")
    end

    it "raises when query is blank" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id, query: nil)

      expect { source.validate_configuration! }.to raise_error("Query is required")
    end

    it "raises when content column is blank" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id, content_column: nil)

      expect { source.validate_configuration! }.to raise_error("Content column is required")
    end

    it "does not raise for a complete configuration" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(
        :rag_steps_sql_database_source,
        connector_id: connector.id,
        query: "SELECT body FROM docs",
        content_column: "body",
      )

      expect { source.validate_configuration! }.not_to raise_error
    end
  end

  describe "#summary" do
    it "uses the selected object name when present" do
      connector = create(:connector, :sql_database, :enabled, name: "My DB")
      source = build(:rag_steps_sql_database_source, connector_id: connector.id, selected_object_name: "articles")

      expect(source.summary).to eq("SQL Database — My DB (articles)")
    end

    it "falls back to the query when no object is selected" do
      connector = create(:connector, :sql_database, :enabled, name: "My DB")
      source = build(:rag_steps_sql_database_source, connector_id: connector.id, query: "SELECT id FROM users")

      expect(source.summary).to eq("SQL Database — My DB (users)")
    end

    it "falls back to an unknown custom query summary" do
      source = described_class.new(query: "SELECT 1")

      expect(source.summary).to eq("SQL Database — unknown (custom query)")
    end
  end

  describe "#execute" do
    it "delegates to SqlDatabaseSourceExecutor" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id)
      allow(Rag::SqlDatabaseSourceExecutor).to receive(:new).and_call_original
      allow_any_instance_of(Rag::SqlDatabaseSourceExecutor).to receive(:call).and_return([]) # rubocop:disable RSpec/AnyInstance

      source.execute([], {})

      expect(Rag::SqlDatabaseSourceExecutor).to have_received(:new).with(source, {})
    end
  end

  describe ".icon" do
    it { expect(described_class.icon).to eq("fa-solid fa-database") }
  end

  describe ".description" do
    it "returns a non-empty description" do
      expect(described_class.description).to include("PostgreSQL database")
    end
  end

  describe ".permitted_params" do
    it "permits wizard fields and metadata arrays" do
      params = ActionController::Parameters.new(
        sql_database_source: {
          connector_id: "1",
          source_mode: "table",
          selected_object_name: "kb_documents",
          selected_object_type: "table",
          content_column: "body",
          metadata_columns: ["title", "category"],
          record_limit: "20",
        },
      )

      result = described_class.permitted_params(params)

      expect(result[:source_mode]).to eq("table")
      expect(result[:selected_object_name]).to eq("kb_documents")
      expect(result[:metadata_columns]).to eq(["title", "category"])
      expect(result[:record_limit]).to eq("20")
    end
  end

  describe "#form_partial_path" do
    it "returns the expected partial path" do
      source = build(:rag_steps_sql_database_source)

      expect(File.directory?(source.form_partial_path)).to be(true)
      expect(File.exist?(File.join(source.form_partial_path, "_form.html.haml"))).to be(true)
    end
  end

  describe "#each_batch" do
    it "delegates to SqlDatabaseSourceExecutor" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id)
      executor = instance_double(Rag::SqlDatabaseSourceExecutor)
      allow(Rag::SqlDatabaseSourceExecutor).to receive(:new).with(source, {}).and_return(executor)
      allow(executor).to receive(:each_batch).and_yield([])

      yielded = []
      source.each_batch({}) { |batch| yielded << batch }

      expect(yielded).to eq([[]])
    end
  end

  describe "#connector" do
    it "returns the connector when connector_id is set" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id)

      expect(source.connector).to eq(connector)
    end

    it "returns nil when connector_id is nil" do
      source = build(:rag_steps_sql_database_source, connector_id: nil)

      expect(source.connector).to be_nil
    end

    it "clears the cached connector when connector_id changes" do
      first_connector = create(:connector, :sql_database, :enabled)
      second_connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: first_connector.id)

      expect(source.connector).to eq(first_connector)

      source.connector_id = second_connector.id

      expect(source.connector).to eq(second_connector)
    end
  end

  describe "#generated_query" do
    it "builds a query without a schema prefix when the connector has no schema name" do
      source = described_class.new(selected_object_name: "documents", content_column: "body")

      expect(source.generated_query).to eq('SELECT "body" FROM "documents"')
    end

    it "returns nil when the selected object name is blank" do
      source = described_class.new(selected_object_name: " ", content_column: "body")

      expect(source.generated_query).to be_nil
    end

    it "returns nil when the content column is blank" do
      source = described_class.new(selected_object_name: "documents", content_column: " ")

      expect(source.generated_query).to be_nil
    end
  end

  describe "#to_configuration" do
    it "returns a serializable hash" do
      connector = create(:connector, :sql_database, :enabled)
      source = build(:rag_steps_sql_database_source, connector_id: connector.id, source_mode: "query")

      expect(source.to_configuration).to include(
        "connector_id" => connector.id,
        "query" => "SELECT id, content FROM documents",
        "source_mode" => "query",
      )
    end
  end
end
