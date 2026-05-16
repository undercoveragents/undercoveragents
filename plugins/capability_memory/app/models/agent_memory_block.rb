# frozen_string_literal: true

# == Schema Information
#
# Table name: agent_memory_blocks
# Database name: primary
#
#  id              :bigint           not null, primary key
#  value           :text             default(""), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  agent_id        :bigint           not null
#  memory_block_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_agent_memory_blocks_on_agent_id         (agent_id)
#  index_agent_memory_blocks_on_memory_block_id  (memory_block_id)
#  index_agent_memory_blocks_on_user_id          (user_id)
#  index_agent_memory_blocks_uniqueness          (agent_id,memory_block_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (memory_block_id => memory_blocks.id)
#  fk_rails_...  (user_id => users.id)
#
class AgentMemoryBlock < ApplicationRecord
  belongs_to :agent
  belongs_to :memory_block
  belongs_to :user

  delegate :label, :description, :char_limit, :read_only?, to: :memory_block

  validates :memory_block_id, uniqueness: {
    scope: [:agent_id, :user_id],
  }
  validates :value, length: { maximum: ->(amb) { amb.memory_block&.char_limit || 0 } }

  def chars_remaining
    char_limit - value.to_s.length
  end

  # Renders this block as XML for injection into the LLM system prompt.
  def render_xml
    memory_block.render_xml(value:)
  end
end
