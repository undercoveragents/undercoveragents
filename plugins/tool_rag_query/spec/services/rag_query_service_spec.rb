# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::RagQueryService do
  let(:sql_database) do
    create(:connector, :sql_database,
           adapter_type: "postgresql",
           host: "localhost",
           database_name: "vector_db",)
  end

  let(:rag_query) do
    create(:tools_rag_query,
           connector: sql_database,
           chunks_table: "chunks",
           documents_table: "documents",
           embedding_field: "embedding",
           chunk_content_field: "content",
           document_reference_field: "document_id",
           document_fields: [{ "name" => "title" }, { "name" => "url" }],
           distance_method: "cosine",
           max_distance: 0.8,
           results_limit: 10,
           llm_connector: create(:connector, :llm_provider, :enabled),
           embedding_model_id: "text-embedding-3-small",)
  end

  let(:service) { described_class.new(sql_database, rag_query:) }

  let(:embedding_vector) { Array.new(1536) { rand(-1.0..1.0) } }

  let(:embedding_response) { double("EmbeddingResponse", vectors: embedding_vector) } # rubocop:disable RSpec/VerifiedDoubles

  describe "#search" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "calls RubyLLM.embed with correct model" do
      allow(service).to receive(:execute_read_only).and_return([])

      service.search("machine learning")

      expect(RubyLLM).to have_received(:embed).with(
        "machine learning",
        model: "text-embedding-3-small",
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
      expect(sql).to include("chunks")
      expect(sql).to include("documents")
      expect(sql).to include("LIMIT 5")
    end

    it "includes document fields in select" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).to include("documents.title AS title")
      expect(sql).to include("documents.url AS url")
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
      rag_query.update!(max_distance: nil)
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).not_to include("WHERE")
    end

    it "formats results with document metadata" do
      rows = [
        { "chunk_content" => "ML basics content", "distance" => "0.1234", "title" => "AI Guide", "url" => "/doc" },
      ]
      allow(service).to receive(:execute_read_only).and_return(rows)

      results = service.search("machine learning", limit: 5)

      expect(results.first[:chunk_content]).to eq("ML basics content")
      expect(results.first[:distance]).to eq(0.1234)
      expect(results.first[:title]).to eq("AI Guide")
      expect(results.first[:url]).to eq("/doc")
    end

    it "uses default limit from rag_query" do
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test")

      expect(sql).to include("LIMIT 10")
    end

    it "raises error when no embedding model configured" do
      rag_query.embedding_model_id = nil
      rag_query.llm_connector_id = nil

      expect { service.search("test") }.to raise_error(RuntimeError, /No embedding model/)
    end
  end

  describe "SQL building with different distance methods" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "uses L2 distance operator" do
      rag_query.update!(distance_method: "l2")
      sql = nil
      allow(service).to receive(:execute_read_only) do |query|
        sql = query
        []
      end

      service.search("test", limit: 5)

      expect(sql).to include("<->")
    end

    it "uses inner product operator" do
      rag_query.update!(distance_method: "inner_product")
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
      rag_query.chunks_table = "chunks; DROP TABLE users"

      expect { service.search("test") }.to raise_error(ArgumentError, /Invalid identifier/)
    end

    it "allows schema-qualified table names" do
      rag_query.chunks_table = "public.chunks"
      allow(service).to receive(:execute_read_only).and_return([])

      expect { service.search("test") }.not_to raise_error
    end
  end

  describe "result formatting edge cases" do
    before do
      allow(RubyLLM).to receive(:embed).and_return(embedding_response)
    end

    it "handles nil distance gracefully" do
      rows = [{ "chunk_content" => "some content", "distance" => nil,
                "title" => "Doc", "url" => "/doc", }]
      allow(service).to receive(:execute_read_only).and_return(rows)

      results = service.search("test")
      expect(results.first[:distance]).to be_nil
    end

    it "handles empty document_fields without error" do
      rag_query.update!(document_fields: [])
      allow(service).to receive(:execute_read_only).and_return(
        [{ "chunk_content" => "content", "distance" => "0.5" }],
      )

      results = service.search("test")
      expect(results.first[:chunk_content]).to eq("content")
    end
  end
end
