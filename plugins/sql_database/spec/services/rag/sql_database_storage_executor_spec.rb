# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::SqlDatabaseStorageExecutor do
  let(:connector) { create(:connector, :sql_database, :enabled) }
  let(:config) do
    build(:rag_steps_sql_database_storage,
          connector_id: connector.id,
          documents_table: "docs",
          chunks_table: "chunks",
          content_field: "content",
          embedding_field: "embedding",
          document_reference_field: "document_id",
          pre_load_action: "none",
          embedding_dimensions: 3,
          auto_create_tables: false,
          upsert_enabled: false,
          metadata_field_mappings: {},
          metadata_column_types: {},)
  end
  let(:executor) { described_class.new(config) }

  let(:mock_conn) { instance_double(PG::Connection) }
  let(:mock_result) { instance_double(PG::Result, first: { "id" => "uuid-1234" }) }

  before do
    allow(PG).to receive(:connect).and_return(mock_conn)
    # Return mock_result for all exec calls (BEGIN/COMMIT/INSERT); return value only needed for INSERT
    allow(mock_conn).to receive_messages(exec: mock_result, exec_params: mock_result)
    allow(mock_conn).to receive(:close)
  end

  describe "#call" do
    let(:chunk) { Rag::Chunk.new(content: "some text", position: 0, embedding: [0.1, 0.2, 0.3]) }
    let(:document) { Rag::Document.new(id: nil, content: "doc content", metadata: {}, chunks: [chunk]) }

    it "begins and commits a transaction" do
      executor.call([document])
      expect(mock_conn).to have_received(:exec).with("BEGIN")
      expect(mock_conn).to have_received(:exec).with("COMMIT")
    end

    it "inserts document and chunks" do
      executor.call([document])
      # Document insert (exec or exec_params)
      expect(mock_conn).to have_received(:exec_params).at_least(:once)
    end

    it "returns the original documents" do
      result = executor.call([document])
      expect(result).to eq([document])
    end

    it "rolls back and re-raises on error" do
      allow(mock_conn).to receive(:exec).with("BEGIN").and_return(nil)
      allow(mock_conn).to receive(:exec).with("COMMIT").and_raise(StandardError, "DB error")
      allow(mock_conn).to receive(:exec).with("ROLLBACK").and_return(nil)

      expect { executor.call([document]) }.to raise_error(StandardError, "DB error")
      expect(mock_conn).to have_received(:exec).with("ROLLBACK")
    end

    it "preserves the original error when rollback fails" do
      allow(mock_conn).to receive(:exec).with("BEGIN").and_return(nil)
      allow(mock_conn).to receive(:exec).with("COMMIT").and_raise(StandardError, "DB error")
      allow(mock_conn).to receive(:exec).with("ROLLBACK").and_raise(StandardError, "rollback failed")

      expect { executor.call([document]) }.to raise_error(StandardError, "DB error")
    end

    it "closes connection even on error" do
      allow(mock_conn).to receive(:exec).with("BEGIN").and_raise(StandardError, "fail")
      allow(mock_conn).to receive(:exec).with("ROLLBACK").and_return(nil)

      expect { executor.call([document]) }.to raise_error(StandardError, "fail")
      expect(mock_conn).to have_received(:close)
    end

    context "with UUID document id" do
      let(:doc_with_id) do
        Rag::Document.new(
          id: "550e8400-e29b-41d4-a716-446655440000",
          content: "text",
          chunks: [chunk],
        )
      end

      it "includes the id in the INSERT" do
        executor.call([doc_with_id])
        expect(mock_conn).to have_received(:exec_params).with(
          /INSERT INTO "docs"/,
          array_including("550e8400-e29b-41d4-a716-446655440000"),
        )
      end
    end

    context "with auto_create_tables enabled" do
      let(:auto_config) do
        build(:rag_steps_sql_database_storage,
              connector_id: connector.id,
              auto_create_tables: true,
              embedding_dimensions: 1536,
              metadata_column_types: {},)
      end
      let(:auto_executor) { described_class.new(auto_config) }

      it "creates tables before storing" do
        auto_executor.call([document])
        expect(mock_conn).to have_received(:exec).with(/CREATE TABLE IF NOT EXISTS/).at_least(:once)
      end
    end

    context "with pre_load_action truncate" do
      let(:truncate_config) do
        build(:rag_steps_sql_database_storage, connector_id: connector.id, pre_load_action: "truncate")
      end
      let(:truncate_executor) { described_class.new(truncate_config) }

      it "truncates tables before storing" do
        truncate_executor.call([document])
        expect(mock_conn).to have_received(:exec).with(/TRUNCATE TABLE/)
      end
    end

    context "with pre_load_action delete_matching" do
      let(:delete_config) do
        build(:rag_steps_sql_database_storage, connector_id: connector.id, pre_load_action: "delete_matching")
      end
      let(:delete_executor) { described_class.new(delete_config) }

      it "deletes rows before storing" do
        delete_executor.call([document])
        expect(mock_conn).to have_received(:exec).with(/DELETE FROM/).at_least(:twice)
      end
    end

    context "with upsert_enabled" do
      let(:upsert_config) do
        build(:rag_steps_sql_database_storage, connector_id: connector.id, upsert_enabled: true)
      end
      let(:upsert_executor) { described_class.new(upsert_config) }
      let(:select_result) { instance_double(PG::Result, first: { "id" => "existing-doc-id" }) }

      before do
        allow(mock_conn).to receive(:exec_params).with(
          /SELECT id FROM "documents" WHERE content_hash = \$1 LIMIT 1/,
          anything,
        ).and_return(select_result)
      end

      it "reuses existing document id by content_hash" do
        upsert_executor.call([document])

        expect(mock_conn).to have_received(:exec_params).with(
          /SELECT id FROM "documents" WHERE content_hash = \$1 LIMIT 1/,
          anything,
        )
      end

      it "updates document metadata fields when mappings are present" do
        mapped_config = build(
          :rag_steps_sql_database_storage,
          connector_id: connector.id,
          upsert_enabled: true,
          metadata_field_mappings: { "author" => "author_col" },
        )
        mapped_executor = described_class.new(mapped_config)
        doc = Rag::Document.new(
          id: nil,
          content: "text",
          metadata: { "author" => "Alice" },
          chunks: [chunk],
        )

        allow(mock_conn).to receive(:exec_params).with(
          /SELECT id FROM "documents" WHERE content_hash = \$1 LIMIT 1/,
          anything,
        ).and_return(select_result)

        mapped_executor.call([doc])

        expect(mock_conn).to have_received(:exec_params).with(
          /UPDATE "documents" SET "author_col" = \$1 WHERE id = \$2/,
          ["Alice", "existing-doc-id"],
        )
      end

      it "replaces old chunks for the reused document id" do
        upsert_executor.call([document])

        expect(mock_conn).to have_received(:exec_params).with(
          /DELETE FROM "chunks" WHERE "document_id" = \$1/,
          ["existing-doc-id"],
        )
      end

      it "falls back to insert when no existing document is found" do
        empty_result = instance_double(PG::Result, first: nil)
        allow(mock_conn).to receive(:exec_params).with(
          /SELECT id FROM/,
          anything,
        ).and_return(empty_result)

        upsert_executor.call([document])
        expect(mock_conn).to have_received(:exec_params).with(/INSERT INTO "documents"/, anything).at_least(:once)
      end

      it "skips metadata update when only id and content_hash columns" do
        doc = Rag::Document.new(id: nil, content: "text", metadata: {}, chunks: [chunk])
        upsert_executor.call([doc])
        # Should NOT attempt an UPDATE since there are no metadata columns
        expect(mock_conn).not_to have_received(:exec_params).with(/UPDATE/, anything)
      end
    end

    context "with chunk without embedding" do
      let(:chunk_no_embed) { Rag::Chunk.new(content: "text", position: 0, embedding: nil) }
      let(:doc_no_embed) { Rag::Document.new(id: nil, content: "doc", chunks: [chunk_no_embed]) }

      it "completes without error (no embedding column in chunk insert)" do
        executor.call([doc_no_embed])
        expect(mock_conn).to have_received(:exec_params).with(
          /INSERT INTO "chunks"/,
          anything,
        )
      end
    end

    context "with metadata field mappings" do
      let(:meta_config) do
        build(:rag_steps_sql_database_storage,
              connector_id: connector.id,
              metadata_field_mappings: { "author" => "author_col" },
              metadata_column_types: {},)
      end
      let(:meta_executor) { described_class.new(meta_config) }

      it "includes metadata in document insert" do
        doc = Rag::Document.new(
          id: nil,
          content: "text",
          metadata: { "author" => "Alice" },
          chunks: [chunk],
        )
        meta_executor.call([doc])
        expect(mock_conn).to have_received(:exec_params).with(
          /INSERT INTO/,
          array_including("Alice"),
        )
      end
    end
  end

  describe "identifier validation" do
    it "raises for invalid identifiers" do
      bad_config = build(:rag_steps_sql_database_storage, connector_id: connector.id,
                                                          documents_table: "drop; table",)
      bad_executor = described_class.new(bad_config)

      # The qi method raises on invalid identifiers
      expect { bad_executor.call([Rag::Document.new(content: "x")]) }.to raise_error(/Invalid identifier/)
    end
  end

  describe "table creation with metadata column types" do
    let(:meta_type_config) do
      build(:rag_steps_sql_database_storage,
            connector_id: connector.id,
            auto_create_tables: true,
            embedding_dimensions: 128,
            metadata_column_types: { "source" => "text", "created_date" => "timestamp" },)
    end
    let(:meta_type_executor) { described_class.new(meta_type_config) }
    let(:document) { Rag::Document.new(content: "text", chunks: []) }

    it "includes metadata columns in documents table creation" do
      meta_type_executor.call([document])
      expect(mock_conn).to have_received(:exec).with(include("source")).at_least(:once)
    end

    it "raises for unsupported SQL types" do
      bad_type_config = build(:rag_steps_sql_database_storage,
                              connector_id: connector.id,
                              auto_create_tables: true,
                              embedding_dimensions: 128,
                              metadata_column_types: { "col" => "blob" },)
      bad_executor = described_class.new(bad_type_config)
      expect { bad_executor.call([document]) }.to raise_error(/Unsupported SQL type/)
    end

    it "raises for invalid embedding_dimensions (zero or negative)" do
      bad_dim_config = build(:rag_steps_sql_database_storage,
                             connector_id: connector.id,
                             auto_create_tables: true,
                             embedding_dimensions: 0,)
      bad_executor = described_class.new(bad_dim_config)
      expect { bad_executor.call([document]) }.to raise_error(/Invalid embedding_dimensions/)
    end
  end

  describe "metadata field mappings" do
    let(:meta_config) do
      build(:rag_steps_sql_database_storage,
            connector_id: connector.id,
            metadata_field_mappings: { "author" => "author_col" },
            metadata_column_types: {},)
    end
    let(:meta_executor) { described_class.new(meta_config) }

    it "includes metadata in document insert when key is present" do
      chunk = Rag::Chunk.new(content: "text", position: 0, embedding: nil)
      doc = Rag::Document.new(
        id: nil,
        content: "text",
        metadata: { "author" => "Alice" },
        chunks: [chunk],
      )
      meta_executor.call([doc])
      expect(mock_conn).to have_received(:exec_params).with(
        /INSERT INTO/,
        array_including("Alice"),
      )
    end

    it "skips metadata key when not present in document metadata" do
      chunk = Rag::Chunk.new(content: "text", position: 0, embedding: nil)
      doc = Rag::Document.new(
        id: nil,
        content: "text",
        metadata: {}, # no "author" key
        chunks: [chunk],
      )
      # Should succeed without raising — the missing metadata key is silently skipped
      expect { meta_executor.call([doc]) }.not_to raise_error
    end
  end

  describe "automatic metadata mapping" do
    let(:auto_config) do
      build(:rag_steps_sql_database_storage,
            connector_id: connector.id,
            metadata_field_mappings: {},
            metadata_column_types: {},)
    end
    let(:auto_executor) { described_class.new(auto_config) }
    let(:chunk) { Rag::Chunk.new(content: "text", position: 0, embedding: nil) }

    it "auto-maps metadata keys to identically-named columns when no explicit mappings" do
      doc = Rag::Document.new(
        id: nil,
        content: "text",
        metadata: { "author" => "Alice", "category" => "tech" },
        chunks: [chunk],
      )
      auto_executor.call([doc])
      expect(mock_conn).to have_received(:exec_params).with(
        /INSERT INTO.*"author".*"category"/,
        array_including("Alice", "tech"),
      )
    end

    it "skips metadata keys with invalid identifier names" do
      doc = Rag::Document.new(
        id: nil,
        content: "text",
        metadata: { "valid_col" => "ok", "has space" => "bad", "123start" => "bad" },
        chunks: [chunk],
      )
      auto_executor.call([doc])
      expect(mock_conn).to have_received(:exec_params).with(
        /INSERT INTO/,
        array_including("ok"),
      )
    end

    context "with auto_create_tables enabled" do
      let(:auto_create_config) do
        build(:rag_steps_sql_database_storage,
              connector_id: connector.id,
              auto_create_tables: true,
              embedding_dimensions: 128,
              metadata_field_mappings: {},
              metadata_column_types: {},)
      end
      let(:auto_create_executor) { described_class.new(auto_create_config) }

      it "auto-creates metadata columns from document metadata keys" do
        doc = Rag::Document.new(
          content: "text",
          metadata: { "author" => "Alice", "category" => "tech" },
          chunks: [],
        )
        auto_create_executor.call([doc])
        expect(mock_conn).to have_received(:exec).with(include("author")).at_least(:once)
        expect(mock_conn).to have_received(:exec).with(include("category")).at_least(:once)
      end

      it "uses explicit column types over auto-detected defaults" do
        config_with_types = build(:rag_steps_sql_database_storage,
                                  connector_id: connector.id,
                                  auto_create_tables: true,
                                  embedding_dimensions: 128,
                                  metadata_field_mappings: {},
                                  metadata_column_types: { "author" => "varchar" },)
        executor_with_types = described_class.new(config_with_types)
        doc = Rag::Document.new(
          content: "text",
          metadata: { "author" => "Alice", "category" => "tech" },
          chunks: [],
        )
        executor_with_types.call([doc])
        # "author" uses explicit "varchar", "category" auto-defaults to "text"
        expect(mock_conn).to have_received(:exec).with(/CREATE TABLE.*author.*varchar/m)
      end

      it "adds missing columns to existing tables via ALTER TABLE" do
        doc = Rag::Document.new(
          content: "text",
          metadata: { "source_url" => "http://example.com" },
          chunks: [],
        )
        auto_create_executor.call([doc])
        expect(mock_conn).to have_received(:exec).with(
          /ALTER TABLE.*ADD COLUMN IF NOT EXISTS.*"source_url".*text/,
        )
      end

      it "silently swallows PG::Error when adding content_hash column" do
        allow(mock_conn).to receive(:exec)
          .with(/ADD COLUMN IF NOT EXISTS content_hash/)
          .and_raise(PG::Error.new("column already exists"))

        doc = Rag::Document.new(content: "text", chunks: [])
        expect { auto_create_executor.call([doc]) }.not_to raise_error
      end
    end
  end

  describe "resolve_connector" do
    it "raises when config.connector is not present" do
      allow(config).to receive(:connector).and_return(nil)
      chunk = Rag::Chunk.new(content: "text", position: 0, embedding: [0.1, 0.2, 0.3])
      doc = Rag::Document.new(id: nil, content: "text", chunks: [chunk])
      expect { executor.call([doc]) }.to raise_error("Connector is required")
    end
  end

  describe "insert_document DEFAULT VALUES fallback" do
    it "uses DEFAULT VALUES insert when column list is empty" do
      allow(executor).to receive(:build_document_columns_and_values).and_return([[], []])
      chunk = Rag::Chunk.new(content: "text", position: 0, embedding: [0.1, 0.2, 0.3])
      doc = Rag::Document.new(id: nil, content: "text", chunks: [chunk])
      executor.call([doc])
      expect(mock_conn).to have_received(:exec).with(/DEFAULT VALUES RETURNING id/)
    end
  end

  describe "document id handling" do
    let(:chunk) { Rag::Chunk.new(content: "text", position: 0, embedding: nil) }

    it "uses exec_params without id when doc id is not a valid UUID" do
      doc = Rag::Document.new(
        id: "non-uuid-doc-id",
        content: "text",
        chunks: [chunk],
      )
      executor.call([doc])
      expect(mock_conn).to have_received(:exec_params).with(
        /INSERT INTO .*\("content_hash"\) VALUES \(\$1\) RETURNING id/,
        array_including(doc.content_hash),
      )
    end
  end

  describe "#fetch_existing_content_hashes" do
    it "returns an empty Set immediately for empty input without querying the DB" do
      result = executor.fetch_existing_content_hashes([])
      expect(result).to be_a(Set)
      expect(result).to be_empty
      # exec_params called inside #call setup only – not for the hash lookup
      expect(mock_conn).not_to have_received(:exec_params).with(/SELECT content_hash/, anything)
    end

    it "queries the DB and returns the matching content hashes" do
      hash_result = instance_double(PG::Result)
      allow(hash_result).to receive(:to_set).and_return(Set.new(["abc123"]))
      allow(mock_conn).to receive(:exec_params)
        .with(/SELECT content_hash/, anything)
        .and_return(hash_result)

      result = executor.fetch_existing_content_hashes(["abc123", "def456"])
      expect(result).to include("abc123")
      expect(mock_conn).to have_received(:close).at_least(:once)
    end

    it "returns an empty Set when the table does not exist (PG::UndefinedTable)" do
      allow(mock_conn).to receive(:exec_params)
        .with(/SELECT content_hash/, anything)
        .and_raise(PG::UndefinedTable.new("no such table"))

      result = executor.fetch_existing_content_hashes(["abc123"])
      expect(result).to be_a(Set)
      expect(result).to be_empty
    end
  end
end
