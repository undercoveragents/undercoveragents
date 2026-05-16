# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::MemoryInsertTool do
  let(:agent) { create(:agent) }
  let(:user)  { create(:user) }
  let(:block) { create(:memory_block, label: "human", default_value: "Existing info", char_limit: 100) }
  let(:amb)   { create(:agent_memory_block, agent:, memory_block: block, user:, value: "Existing info") }
  let(:tool)  { described_class.for_agent(agent, user:) }

  before { amb }

  describe ".for_agent" do
    it "returns a tool instance bound to the given agent" do
      tool = described_class.for_agent(agent, user:)
      expect(tool).to be_a(described_class)
    end
  end

  describe "#name" do
    it "returns 'memory_insert'" do
      expect(tool.name).to eq("memory_insert")
    end
  end

  describe "#execute" do
    it "appends text to the block on a new line" do
      result = tool.execute(block_label: "human", text: "Likes Ruby")

      expect(result[:success]).to be(true)
      expect(amb.reload.value).to eq("Existing info\nLikes Ruby")
    end

    it "handles block with empty value" do
      amb.update!(value: "")
      result = tool.execute(block_label: "human", text: "First entry")

      expect(result[:success]).to be(true)
      expect(amb.reload.value).to eq("First entry")
    end

    it "returns char usage info" do
      result = tool.execute(block_label: "human", text: "Test")

      expect(result[:chars_used]).to be_positive
      expect(result).to have_key(:chars_remaining)
      expect(result).to have_key(:chars_limit)
    end

    it "returns error when block is not found" do
      result = tool.execute(block_label: "nonexistent", text: "test")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("not found")
    end

    it "returns error when block is read-only" do
      block.update!(read_only: true)
      result = tool.execute(block_label: "human", text: "test")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("read-only")
    end

    it "returns error when appending would exceed char_limit" do
      amb.update!(value: "a" * 95)
      result = tool.execute(block_label: "human", text: "too much content here")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("exceeding limit")
    end
  end
end
