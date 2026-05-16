# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseSourceExecutor do
  let(:connector) { create(:connector, :sql_database, :enabled) }
  let(:config) do
    build(:rag_steps_sql_database_source, connector_id: connector.id,
                                          query: "SELECT id, body FROM posts", content_column: "body",
                                          batch_size: 2,)
  end
  let(:executor) { described_class.new(config, {}) }

  let(:mock_conn) { instance_double(PG::Connection) }
  let(:rows) { [{ "id" => "1", "body" => "Hello world" }, { "id" => "2", "body" => "Second doc" }] }
  let(:mock_result) { instance_double(PG::Result, to_a: rows) }
  let(:empty_result) { instance_double(PG::Result, to_a: []) }

  before do
    allow(PG).to receive(:connect).and_return(mock_conn)
    allow(mock_conn).to receive(:exec).and_return(nil)
    allow(mock_conn).to receive(:close)
  end

  describe "#call" do
    before do
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)
    end

    it "returns all documents collected across batches" do
      result = executor.call
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.map(&:content)).to eq(["Hello world", "Second doc"])
    end
  end

  describe "#each_batch" do
    before do
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)
    end

    it "yields document batches" do
      batches = []
      executor.each_batch { |batch| batches << batch }

      expect(batches.length).to eq(1)
      expect(batches.first.length).to eq(2)
    end

    it "builds Rag::Document objects" do
      docs = []
      executor.each_batch { |batch| docs.concat(batch) }

      expect(docs.first).to be_a(Rag::Document)
      expect(docs.first.content).to eq("Hello world")
    end

    it "extracts metadata columns" do
      config_with_meta = build(:rag_steps_sql_database_source,
                               connector_id: connector.id,
                               content_column: "body",
                               metadata_columns: ["id"],
                               query: "SELECT id, body FROM posts",
                               batch_size: 10,)
      exec = described_class.new(config_with_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to include("id" => "1")
    end

    it "returns empty metadata when metadata_columns is nil" do
      config_nil_meta = build(:rag_steps_sql_database_source,
                              connector_id: connector.id,
                              content_column: "body",
                              query: "SELECT body FROM posts",
                              batch_size: 10,)
      allow(config_nil_meta).to receive(:metadata_columns).and_return(nil)
      exec = described_class.new(config_nil_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to eq({})
    end

    it "returns empty metadata when metadata_columns is not an array" do
      config_invalid_meta = build(:rag_steps_sql_database_source,
                                  connector_id: connector.id,
                                  content_column: "body",
                                  query: "SELECT body FROM posts",
                                  batch_size: 10,)
      allow(config_invalid_meta).to receive(:metadata_columns).and_return("id")
      exec = described_class.new(config_invalid_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to eq({})
    end

    it "extracts metadata for hash-format column configs" do
      config_hash_meta = build(:rag_steps_sql_database_source,
                               connector_id: connector.id,
                               content_column: "body",
                               query: "SELECT id, body FROM posts",
                               batch_size: 10,)
      allow(config_hash_meta).to receive(:metadata_columns).and_return([{ "name" => "id" }])
      exec = described_class.new(config_hash_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to include("id" => "1")
    end

    it "extracts metadata for hash-format column configs with symbol keys" do
      config_hash_meta = build(:rag_steps_sql_database_source,
                               connector_id: connector.id,
                               content_column: "body",
                               query: "SELECT id, body FROM posts",
                               batch_size: 10,)
      allow(config_hash_meta).to receive(:metadata_columns).and_return([{ name: "id" }])
      exec = described_class.new(config_hash_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to include("id" => "1")
    end

    it "ignores hash metadata entries without a usable name" do
      config_hash_meta = build(:rag_steps_sql_database_source,
                               connector_id: connector.id,
                               content_column: "body",
                               query: "SELECT id, body FROM posts",
                               batch_size: 10,)
      allow(config_hash_meta).to receive(:metadata_columns).and_return([{}])
      exec = described_class.new(config_hash_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).to eq({})
    end

    it "omits metadata columns not present in the result row" do
      config_missing_meta = build(:rag_steps_sql_database_source,
                                  connector_id: connector.id,
                                  content_column: "body",
                                  metadata_columns: ["nonexistent_column"],
                                  query: "SELECT body FROM posts",
                                  batch_size: 10,)
      exec = described_class.new(config_missing_meta, {})
      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, empty_result)

      docs = []
      exec.each_batch { |batch| docs.concat(batch) }

      expect(docs.first.metadata).not_to have_key("nonexistent_column")
    end

    it "closes the connection even on error" do
      allow(mock_conn).to receive(:exec).with("BEGIN TRANSACTION READ ONLY").and_raise(StandardError, "fail")

      expect { executor.each_batch { |_batch| nil } }.to raise_error(StandardError, "fail")
      expect(mock_conn).to have_received(:close)
    end

    it "handles multiple batches" do
      rows_batch2 = [{ "id" => "3", "body" => "Third" }]
      result_batch2 = instance_double(PG::Result, to_a: rows_batch2)

      allow(mock_conn).to receive(:exec).with(/FETCH/).and_return(mock_result, result_batch2, empty_result)

      all_docs = []
      executor.each_batch { |batch| all_docs.concat(batch) }
      expect(all_docs.length).to eq(3)
    end
  end

  describe "adapter validation" do
    it "raises for non-postgresql adapters" do
      config_with_conn = build(:rag_steps_sql_database_source, connector_id: connector.id)
      allow_any_instance_of(Connectors::SqlDatabase).to receive(:adapter_type).and_return("mysql") # rubocop:disable RSpec/AnyInstance

      exec = described_class.new(config_with_conn, {})
      expect { exec.each_batch { |_batch| nil } }.to raise_error(/PostgreSQL/)
    end
  end
end
