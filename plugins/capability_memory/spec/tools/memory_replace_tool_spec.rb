# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::MemoryReplaceTool do
  let(:agent) { create(:agent) }
  let(:user)  { create(:user) }
  let(:block) { create(:memory_block, label: "persona", default_value: "Old content", char_limit: 100) }
  let(:amb)   { create(:agent_memory_block, agent:, memory_block: block, user:, value: "Old content") }
  let(:tool)  { described_class.for_agent(agent, user:) }

  before { amb }

  describe ".for_agent" do
    it "returns a tool instance bound to the given agent" do
      tool = described_class.for_agent(agent, user:)
      expect(tool).to be_a(described_class)
    end
  end

  describe "#name" do
    it "returns 'memory_replace'" do
      expect(tool.name).to eq("memory_replace")
    end
  end

  describe "#execute" do
    it "replaces the block's value" do
      result = tool.execute(block_label: "persona", new_value: "New persona content")

      expect(result[:success]).to be(true)
      expect(amb.reload.value).to eq("New persona content")
    end

    it "returns char usage info" do
      result = tool.execute(block_label: "persona", new_value: "Hello")

      expect(result[:chars_used]).to eq(5)
      expect(result[:chars_remaining]).to eq(95)
      expect(result[:chars_limit]).to eq(100)
    end

    it "returns error when block is not found" do
      result = tool.execute(block_label: "nonexistent", new_value: "test")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("not found")
    end

    it "returns error when block is read-only" do
      block.update!(read_only: true)
      result = tool.execute(block_label: "persona", new_value: "test")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("read-only")
    end

    it "returns error when content exceeds char_limit" do
      result = tool.execute(block_label: "persona", new_value: "a" * 101)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("exceeds limit")
    end
  end
end
