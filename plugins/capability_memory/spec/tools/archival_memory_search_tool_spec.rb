# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::ArchivalMemorySearchTool do
  let(:agent)             { create(:agent) }
  let(:user)              { create(:user) }
  let(:embedding_service) { instance_double(Capabilities::Memory::EmbeddingService) }
  let(:tool)              { described_class.for_agent(agent, user:, embedding_service:) }
  let(:query_embedding)   { Array.new(1536) { 0.5 } }

  before do
    allow(embedding_service).to receive(:embed).and_return(query_embedding)
  end

  describe ".for_agent" do
    it "returns a tool instance bound to the agent and embedding service" do
      result = described_class.for_agent(agent, user:, embedding_service:)
      expect(result).to be_a(described_class)
    end
  end

  describe "#name" do
    it "returns 'archival_memory_search'" do
      expect(tool.name).to eq("archival_memory_search")
    end
  end

  describe "#execute" do
    before do
      create(:archival_memory, agent:, user:, content: "Ruby is great",
                               embedding: query_embedding, tags: ["programming"],)
      create(:archival_memory, agent:, user:, content: "Rails conventions",
                               embedding: query_embedding, tags: ["programming"],)
    end

    it "returns search results with metadata" do
      result = tool.execute(query: "Ruby programming")

      expect(result[:results]).to be_an(Array)
      expect(result[:count]).to eq(2)
      expect(result[:query]).to eq("Ruby programming")
    end

    it "passes query to embedding service for vectorization" do
      tool.execute(query: "test query")

      expect(embedding_service).to have_received(:embed).with("test query")
    end

    it "returns results with expected shape" do
      result = tool.execute(query: "Ruby")
      first  = result[:results].first

      expect(first).to have_key(:id)
      expect(first).to have_key(:content)
      expect(first).to have_key(:tags)
      expect(first).to have_key(:created_at)
    end

    it "handles pagination" do
      result = tool.execute(query: "Ruby", page: 1)

      expect(result[:page]).to eq(1)
    end

    it "only returns memories belonging to the current user" do
      other_user = create(:user)
      create(:archival_memory, agent:, user: other_user, content: "Other user memory",
                               embedding: query_embedding,)

      result = tool.execute(query: "Ruby")

      contents = result[:results].pluck(:content)
      expect(contents).not_to include("Other user memory")
    end

    it "returns error when embedding fails" do
      allow(embedding_service).to receive(:embed).and_raise(StandardError, "API down")

      result = tool.execute(query: "broken query")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("API down")
    end
  end
end
