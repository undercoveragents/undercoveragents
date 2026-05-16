# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentMemoryBlock do
  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:memory_block) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject(:agent_memory_block_record) { create(:agent_memory_block) }

    it {
      expect(agent_memory_block_record).to validate_uniqueness_of(:memory_block_id)
        .scoped_to(:agent_id, :user_id)
    }
  end

  describe "creating duplicates" do
    it "prevents attaching the same block to the same agent+user twice" do
      existing = create(:agent_memory_block)
      duplicate = build(:agent_memory_block, agent: existing.agent,
                                             memory_block: existing.memory_block,
                                             user: existing.user,)

      expect(duplicate).not_to be_valid
    end

    it "allows the same block for different users on the same agent" do
      existing   = create(:agent_memory_block)
      other_user = create(:user)
      other      = build(:agent_memory_block, agent: existing.agent,
                                              memory_block: existing.memory_block,
                                              user: other_user,)

      expect(other).to be_valid
    end
  end

  describe "#render_xml" do
    it "delegates to memory_block.render_xml with the user-specific value" do
      block = create(:memory_block, label: "persona", default_value: "default seed", char_limit: 5000)
      amb   = create(:agent_memory_block, memory_block: block, value: "user override")
      xml   = amb.render_xml

      expect(xml).to include("<persona>")
      expect(xml).to include("user override")
      expect(xml).not_to include("default seed")
    end
  end

  describe "#chars_remaining" do
    it "returns char_limit minus current value length" do
      block = create(:memory_block, char_limit: 100, default_value: "")
      amb   = create(:agent_memory_block, memory_block: block, value: "hello")

      expect(amb.chars_remaining).to eq(95)
    end
  end
end
