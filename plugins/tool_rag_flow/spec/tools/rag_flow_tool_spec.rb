# frozen_string_literal: true

require "rails_helper"

RSpec.describe RagFlowTool do
  let(:rag_flow) { create(:tools_rag_flow) }

  let(:tool_record) do
    create(:tool, :enabled, name: "Flow Knowledge Search", toolable: rag_flow)
  end

  describe ".for_tool" do
    it "creates a tool instance for a RAG tool" do
      tool = described_class.for_tool(tool_record)

      expect(tool).to be_a(described_class)
    end

    it "raises for non-RAG tools" do
      sql_tool = create(:tool, :sql_query)

      expect do
        described_class.for_tool(sql_tool)
      end.to raise_error(ArgumentError, /RAG tool/)
    end
  end

  describe "#name" do
    it "derives a unique tool name from the tool record name" do
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to eq("rag_flow_flow_knowledge_search")
    end

    it "sanitizes special characters in tool names" do
      tool_record.update!(name: "My Flow (v2) #1")
      tool = described_class.for_tool(tool_record)

      expect(tool.name).to match(/\Arag_flow_[a-z0-9_]+\z/)
    end
  end

  describe "#description" do
    it "returns the default tool prompt when no custom instructions" do
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to eq(Tools::RagSearchable::DEFAULT_TOOL_PROMPT)
    end

    it "returns custom instructions when set" do
      rag_flow.update!(custom_instructions: "Search the knowledge base for docs")
      tool = described_class.for_tool(tool_record)

      expect(tool.description).to eq("Search the knowledge base for docs")
    end
  end

  describe "#execute" do
    let(:tool) { described_class.for_tool(tool_record) }
    let(:service_double) { instance_double(Tools::RagSearchService) }

    before do
      allow(Tools::RagSearchService).to receive(:new).and_return(service_double)
    end

    it "searches and returns formatted results" do
      results = [{ chunk_content: "ML basics", distance: 0.1234, title: "AI Guide" }]
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

    it "passes llm_context from the embedding step's llm_connector" do
      context_double = double("LlmContext") # rubocop:disable RSpec/VerifiedDoubles
      toolable = tool_record.toolable
      allow(toolable).to receive(:llm_connector).and_return(
        double("Connector", build_context: context_double), # rubocop:disable RSpec/VerifiedDoubles
      )

      allow(service_double).to receive(:search).and_return([])
      tool.execute(query: "test")

      expect(Tools::RagSearchService).to have_received(:new).with(
        anything, hash_including(llm_context: context_double),
      )
    end

    it "passes nil llm_context when connector is nil" do
      toolable = tool_record.toolable
      null_conn = double("Connector", build_context: nil) # rubocop:disable RSpec/VerifiedDoubles
      allow(toolable).to receive(:llm_connector).and_return(null_conn)
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
