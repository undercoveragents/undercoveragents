# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::Bootstrapper do
  let(:agent) { create(:agent) }
  let(:user)  { create(:user) }

  describe "#bootstrap!" do
    it "creates persona and human AgentMemoryBlock records for the user" do
      blocks = described_class.new(agent, user:).bootstrap!

      labels = blocks.map(&:label)
      expect(labels).to include("persona", "human")
      expect(agent.user_memory_blocks(user).count).to eq(2)
    end

    it "sets initial values when provided" do
      blocks = described_class.new(
        agent,
        user:,
        persona: "I am a formal assistant.",
        human: "The user is an engineer.",
      ).bootstrap!

      persona = blocks.find { |b| b.label == "persona" }
      human   = blocks.find { |b| b.label == "human" }

      expect(persona.value).to eq("I am a formal assistant.")
      expect(human.value).to eq("The user is an engineer.")
    end

    it "is idempotent — does not duplicate blocks for the same user" do
      described_class.new(agent, user:).bootstrap!
      described_class.new(agent, user:).bootstrap!

      expect(agent.user_memory_blocks(user).count).to eq(2)
    end

    it "creates separate rows for different users" do
      other_user = create(:user)
      described_class.new(agent, user:).bootstrap!
      described_class.new(agent, user: other_user).bootstrap!

      expect(agent.user_memory_blocks(user).count).to eq(2)
      expect(agent.user_memory_blocks(other_user).count).to eq(2)
    end

    it "attaches shared blocks when shared_block_ids is provided" do
      shared_block = create(:memory_block, :read_only, label: "policy")
      blocks = described_class.new(agent, user:, shared_block_ids: [shared_block.id]).bootstrap!

      expect(blocks.map(&:label)).to include("policy")
    end

    it "wraps creation in a transaction" do
      call_count = 0
      allow(MemoryBlock).to receive(:find_or_create_by!).and_wrap_original do |orig, *args, &blk|
        call_count += 1
        raise ActiveRecord::RecordInvalid if call_count == 2

        orig.call(*args, &blk)
      end

      expect do
        described_class.new(agent, user:).bootstrap!
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(agent.user_memory_blocks(user).count).to eq(0)
    end
  end
end
