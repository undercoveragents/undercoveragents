# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagQueryTool do
  let(:connector) do
    create(:connector, :sql_database, :enabled, name: "Vector DB",
                                                adapter_type: "postgresql",
                                                host: "localhost",
                                                database_name: "vector_db",)
  end

  let(:llm_connector) do
    create(:connector, :llm_provider, :enabled, name: "Embedding LLM")
  end

  let(:rag_query) do
    create(:tools_rag_query,
           connector:,
           llm_connector:,
           embedding_model_id: "text-embedding-3-small",
           chunks_table: "chunks",
           documents_table: "documents",
           embedding_field: "embedding",
           chunk_content_field: "content",
           document_reference_field: "document_id",
           document_fields: [{ "name" => "title" }, { "name" => "url" }],
           distance_method: "cosine",
           max_distance: 0.8,
           results_limit: 10,)
  end

  let(:tool_record) do
    create(:tool, :enabled, name: "Knowledge Base Search", toolable: rag_query)
  end

  describe ".for_tool" do
    it "creates a tool instance for a RAG Query tool" do
      tool = described_class.for_tool(tool_record)

      expect(tool).to be_a(described_class)
    end

    it "raises for non-RAG Query tools" do
      sql_tool = create(:tool, :sql_query)

      expect do
        described_class.for_tool(sql_tool)
      end.to raise_error(ArgumentError, /RAG Query tool/)
    end
  end

  describe "#name" do
    it "derives a unique tool name from the tool record name" do
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to eq("rag_query_knowledge_base_search")
    end

    it "sanitizes special characters in tool names" do
      tool_record.update!(name: "My KB (Production) #1")
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to match(/\Arag_query_[a-z0-9_]+\z/)
    end
  end

  describe "#description" do
    it "returns the default tool prompt when no custom instructions" do
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to eq(Tools::RagSearchable::DEFAULT_TOOL_PROMPT)
    end

    it "returns custom instructions when set" do
      rag_query.update!(custom_instructions: "Search the knowledge base for technical docs")
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to eq("Search the knowledge base for technical docs")
    end
  end

  describe "#execute" do
    let(:tool) { described_class.for_tool(tool_record) }
    let(:service_double) { instance_double(Tools::RagSearchService) }

    before do
      allow(Tools::RagSearchService).to receive(:new).and_return(service_double)
    end

    it "searches and returns formatted results" do
      results = [{ chunk_content: "ML basics", distance: 0.1234, title: "AI Guide", url: "/docs/ai" }]
      allow(service_double).to receive(:search).with("machine learning", limit: 10).and_return(results)

      result = tool.execute(query: "machine learning")

      expect(result).to include("ML basics")
      expect(result).to include("AI Guide")
    end

    it "uses configured results_limit by default" do
      allow(service_double).to receive(:search).with("test", limit: 10).and_return([])

      tool.execute(query: "test")

      expect(service_double).to have_received(:search).with("test", limit: 10)
    end

    it "overrides limit when provided" do
      allow(service_double).to receive(:search).with("test", limit: 5).and_return([])

      tool.execute(query: "test", limit: 5)

      expect(service_double).to have_received(:search).with("test", limit: 5)
    end

    it "returns error message on failure" do
      allow(service_double).to receive(:search).and_raise(StandardError.new("connection failed"))
      allow(Rails.logger).to receive(:error)

      result = tool.execute(query: "test")

      expect(result).to include("couldn't execute")
      expect(result).to include("connection failed")
    end

    it "returns no-results message for empty results" do
      allow(service_double).to receive(:search).and_return([])

      result = tool.execute(query: "nonexistent topic")

      expect(result).to eq("No relevant chunks found.")
    end

    it "returns no-results message for nil results" do
      allow(service_double).to receive(:search).and_return(nil)

      result = tool.execute(query: "nothing")

      expect(result).to eq("No relevant chunks found.")
    end

    it "passes llm_context from the llm_connector" do
      context_double = double("LlmContext") # rubocop:disable RSpec/VerifiedDoubles
      allow(llm_connector).to receive(:build_context).and_return(context_double)

      allow(service_double).to receive(:search).and_return([])
      tool.execute(query: "test")

      expect(Tools::RagSearchService).to have_received(:new).with(
        anything, hash_including(llm_context: context_double),
      )
    end

    it "passes nil llm_context when llm_connector_id is blank" do
      rag_query.llm_connector_id = nil
      allow(service_double).to receive(:search).and_return([])
      tool.execute(query: "test")

      expect(Tools::RagSearchService).to have_received(:new).with(
        anything, hash_including(llm_context: nil),
      )
    end

    it "passes nil llm_context when llm_connector_id is set but connector is missing" do
      tool # eagerly build tool_record before stubbing
      # llm_connector_id is present but the connector record returns nil (deleted)
      allow(rag_query).to receive(:llm_connector).and_return(nil)
      allow(service_double).to receive(:search).and_return([])
      tool.execute(query: "test")

      expect(Tools::RagSearchService).to have_received(:new).with(
        anything, hash_including(llm_context: nil),
      )
    end
  end

  describe "#parameters" do
    let(:tool) { described_class.for_tool(tool_record) }

    it "has a required query parameter" do
      expect(tool.parameters[:query]).to be_present
      expect(tool.parameters[:query].required).to be(true)
    end

    it "has an optional limit parameter" do
      expect(tool.parameters[:limit]).to be_present
      expect(tool.parameters[:limit].required).to be(false)
    end
  end
end
