# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::RagSearchService do
  let(:rag_flow) { create(:tools_rag_flow, distance_method: "cosine", max_distance: 0.8, results_limit: 10) }

  let(:service) { described_class.new(rag_flow) }

  let(:embedding_vector) { Array.new(1536) { rand(-1.0..1.0) } }

  let(:embedding_response) { double("EmbeddingResponse", vectors: embedding_vector) } # rubocop:disable RSpec/VerifiedDoubles

  describe "#search" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "calls RubyLLM.embed with the embedding model from the searchable" do
      allow(service).to receive(:execute_read_only).and_return([])

      service.search("machine learning")

      expect(RubyLLM).to have_received(:embed).with(
        "machine learning",
        model: rag_flow.embedding_model_id,
        context: nil,
      )
    end

    it "builds SQL with cosine distance operator" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test query", limit: 5)

      expect(sql).to include("<=>")
      expect(sql).to include(rag_flow.chunks_table)
      expect(sql).to include(rag_flow.documents_table)
      expect(sql).to include("LIMIT 5")
    end

    it "includes document fields in select" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      rag_flow.selected_document_fields.each do |field|
        expect(sql).to include("#{rag_flow.documents_table}.#{field} AS #{field}")
      end
    end

    it "includes max_distance filter" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).to include("<= 0.8")
    end

    it "omits max_distance filter when nil" do
      rag_flow.max_distance = nil
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).not_to include("WHERE")
    end

    it "formats results with document metadata" do
      step = rag_flow.rag_flow.step_for(:storage)
      step.update!(configuration: step.configuration.merge("metadata_field_mappings" => { "src_title" => "title" }))
      rows = [
        { "chunk_content" => "Content here", "distance" => "0.1234", "title" => "Doc Title" },
      ]
      allow(service).to receive(:execute_read_only).and_return(rows)

      results = service.search("query", limit: 5)

      expect(results.first[:chunk_content]).to eq("Content here")
      expect(results.first[:distance]).to eq(0.1234)
      expect(results.first[:title]).to eq("Doc Title")
    end

    it "uses default limit from searchable" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test")

      expect(sql).to include("LIMIT 10")
    end

    it "raises error when no embedding model configured" do
      allow(rag_flow).to receive(:embedding_model_id).and_return(nil)

      expect { service.search("test") }.to raise_error(RuntimeError, /No embedding model/)
    end
  end

  describe "SQL building with different distance methods" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "uses L2 distance operator" do
      rag_flow.distance_method = "l2"
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).to include("<->")
    end

    it "uses inner product operator" do
      rag_flow.distance_method = "inner_product"
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).to include("<#>")
    end
  end

  describe "identifier sanitization" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "rejects invalid identifiers" do
      allow(rag_flow).to receive(:chunks_table).and_return("chunks; DROP TABLE users")

      expect { service.search("test") }.to raise_error(ArgumentError, /Invalid identifier/)
    end

    it "allows schema-qualified table names" do
      allow(rag_flow).to receive(:chunks_table).and_return("public.chunks")
      allow(service).to receive(:execute_read_only).and_return([])

      expect { service.search("test") }.not_to raise_error
    end
  end

  describe "result formatting edge cases" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "handles nil distance gracefully" do
      rows = [{ "chunk_content" => "some content", "distance" => nil, "title" => "Doc" }]
      allow(service).to receive(:execute_read_only).and_return(rows)

      results = service.search("test")
      expect(results.first[:distance]).to be_nil
    end

    it "handles empty document_fields without error" do
      rag_flow.document_fields = []
      allow(service).to receive(:execute_read_only).and_return(
        [{ "chunk_content" => "content", "distance" => "0.5" }],
      )

      results = service.search("test")
      expect(results.first[:chunk_content]).to eq("content")
    end
  end

  describe "database execution helpers" do
    it "wraps queries in a read-only transaction" do
      conn = double("PG::Connection") # rubocop:disable RSpec/VerifiedDoubles
      rows = [{ "chunk_content" => "content" }]
      result = double("PG::Result", to_a: rows) # rubocop:disable RSpec/VerifiedDoubles

      allow(conn).to receive(:exec).with("BEGIN")
      allow(conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
      allow(conn).to receive(:exec).with("SELECT 1").and_return(result)
      allow(conn).to receive(:exec).with("ROLLBACK")
      allow(service).to receive(:with_pg_connection).and_yield(conn)

      expect(service.send(:execute_read_only, "SELECT 1")).to eq(rows)
    end

    it "rolls back and re-raises when query execution fails" do
      conn = double("PG::Connection") # rubocop:disable RSpec/VerifiedDoubles

      allow(conn).to receive(:exec).with("BEGIN")
      allow(conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
      allow(conn).to receive(:exec).with("SELECT 1").and_raise(StandardError, "query failed")
      allow(conn).to receive(:exec).with("ROLLBACK")
      allow(service).to receive(:with_pg_connection).and_yield(conn)

      expect { service.send(:execute_read_only, "SELECT 1") }
        .to raise_error(StandardError, "query failed")
    end

    it "preserves the query error when rollback fails" do
      conn = double("PG::Connection") # rubocop:disable RSpec/VerifiedDoubles

      allow(conn).to receive(:exec).with("BEGIN")
      allow(conn).to receive(:exec).with("SET TRANSACTION READ ONLY")
      allow(conn).to receive(:exec).with("SELECT 1").and_raise(StandardError, "query failed")
      allow(conn).to receive(:exec).with("ROLLBACK").and_raise(StandardError, "rollback failed")
      allow(service).to receive(:with_pg_connection).and_yield(conn)

      expect { service.send(:execute_read_only, "SELECT 1") }
        .to raise_error(StandardError, "query failed")
    end

    it "closes the pg connection after yielding" do
      conn = double("PG::Connection") # rubocop:disable RSpec/VerifiedDoubles
      sql_database = double("Connectors::SqlDatabase") # rubocop:disable RSpec/VerifiedDoubles

      allow(conn).to receive(:close)
      allow(rag_flow).to receive(:sql_database).and_return(sql_database)
      allow(service).to receive(:build_pg_config_for).with(sql_database).and_return({ "dbname" => "rag" })
      allow(service).to receive(:connect_pg).with({ "dbname" => "rag" }).and_return(conn)

      yielded_connection = nil
      service.send(:with_pg_connection) { |connection| yielded_connection = connection }

      expect(yielded_connection).to eq(conn)
      expect(conn).to have_received(:close)
    end
  end
end
