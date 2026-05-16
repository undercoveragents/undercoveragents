# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::ArchivalMemoryInsertTool do
  let(:agent)             { create(:agent) }
  let(:user)              { create(:user) }
  let(:embedding_service) { instance_double(Capabilities::Memory::EmbeddingService) }
  let(:tool)              { described_class.for_agent(agent, user:, embedding_service:) }
  let(:fake_embedding)    { Array.new(1536) { rand(-1.0..1.0) } }

  before do
    allow(embedding_service).to receive(:embed).and_return(fake_embedding)
  end

  describe ".for_agent" do
    it "returns a tool instance bound to the agent and embedding service" do
      result = described_class.for_agent(agent, user:, embedding_service:)
      expect(result).to be_a(described_class)
    end
  end

  describe "#name" do
    it "returns 'archival_memory_insert'" do
      expect(tool.name).to eq("archival_memory_insert")
    end
  end

  describe "#execute" do
    it "creates an archival memory for the user with embedding" do
      result = tool.execute(content: "Important fact about the project")

      expect(result[:success]).to be(true)
      expect(result[:content_preview]).to include("Important fact")
      expect(ArchivalMemory.where(agent:, user:).count).to eq(1)
    end

    it "passes content to embedding service" do
      tool.execute(content: "Some content to embed")

      expect(embedding_service).to have_received(:embed).with("Some content to embed")
    end

    it "stores optional tags" do
      result = tool.execute(content: "Tagged memory", tags: ["work", "rails"])

      expect(result[:tags]).to eq(["work", "rails"])
      expect(ArchivalMemory.where(agent:, user:).last.tags).to eq(["work", "rails"])
    end

    it "returns error when embedding fails" do
      allow(embedding_service).to receive(:embed).and_raise(StandardError, "API error")

      result = tool.execute(content: "Will fail")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("API error")
    end
  end
end
