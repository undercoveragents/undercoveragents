# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::AgentExtension do
  let(:agent)        { create(:agent) }
  let(:memory_block) { create(:memory_block) }
  let(:user)         { create(:user) }

  describe "associations" do
    it "has many agent_memory_blocks" do
      expect(agent).to respond_to(:agent_memory_blocks)
    end

    it "has many archival_memories" do
      expect(agent).to respond_to(:archival_memories)
    end
  end

  describe "#user_memory_blocks" do
    it "returns AgentMemoryBlock records for the given user" do
      amb         = create(:agent_memory_block, agent:, memory_block:, user:)
      other_user  = create(:user)
      _other_amb  = create(:agent_memory_block, agent:, memory_block: create(:memory_block), user: other_user)

      expect(agent.user_memory_blocks(user)).to eq([amb])
    end
  end

  describe "#agent_memory_block_for" do
    it "returns the AgentMemoryBlock matching label + user" do
      create(:agent_memory_block, agent:, memory_block:, user:)

      result = agent.agent_memory_block_for(label: memory_block.label, user:)
      expect(result).to be_a(AgentMemoryBlock)
    end

    it "returns nil when no matching record exists" do
      expect(agent.agent_memory_block_for(label: "ghost", user:)).to be_nil
    end
  end

  describe "#attach_memory_block_for_user" do
    it "creates an AgentMemoryBlock for the given user" do
      expect { agent.attach_memory_block_for_user(memory_block, user:) }
        .to change { AgentMemoryBlock.where(agent:, user:).count }.by(1)
    end

    it "is idempotent" do
      agent.attach_memory_block_for_user(memory_block, user:)

      expect { agent.attach_memory_block_for_user(memory_block, user:) }
        .not_to(change { AgentMemoryBlock.where(agent:, user:).count })
    end
  end

  describe "#detach_memory_block_for_user" do
    before { agent.attach_memory_block_for_user(memory_block, user:) }

    it "removes the AgentMemoryBlock for the given user" do
      expect { agent.detach_memory_block_for_user(memory_block, user:) }
        .to change { AgentMemoryBlock.where(agent:, user:).count }.by(-1)
    end

    it "does not delete the MemoryBlock template itself" do
      agent.detach_memory_block_for_user(memory_block, user:)

      expect(MemoryBlock.exists?(memory_block.id)).to be(true)
    end

    it "returns nil when no matching record exists" do
      agent.detach_memory_block_for_user(memory_block, user:)

      expect(agent.detach_memory_block_for_user(memory_block, user:)).to be_nil
    end
  end

  describe "#memory_configured_for?" do
    it "returns false when no AgentMemoryBlock exists for the user" do
      expect(agent.memory_configured_for?(user)).to be(false)
    end

    it "returns true when AgentMemoryBlock records exist for the user" do
      create(:agent_memory_block, agent:, memory_block:, user:)

      expect(agent.memory_configured_for?(user)).to be(true)
    end
  end

  describe "#memory_configured?" do
    it "returns false when no blocks are attached at all" do
      expect(agent.memory_configured?).to be(false)
    end

    it "returns true when any user has blocks attached" do
      create(:agent_memory_block, agent:, memory_block:, user:)

      expect(agent.memory_configured?).to be(true)
    end
  end
end
