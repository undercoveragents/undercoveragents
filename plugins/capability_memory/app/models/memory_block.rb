# frozen_string_literal: true

# == Schema Information
#
# Table name: memory_blocks
# Database name: primary
#
#  id            :bigint           not null, primary key
#  char_limit    :integer          default(5000), not null
#  default_value :text             default(""), not null
#  description   :text
#  label         :string           not null
#  read_only     :boolean          default(FALSE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_memory_blocks_on_label  (label)
#
class MemoryBlock < ApplicationRecord
  # MemoryBlock is a global template: it defines the slot (label, description,
  # char_limit, read_only) and a default value used when bootstrapping a new user.
  # Actual user-specific values live on AgentMemoryBlock.
  has_many :agent_memory_blocks, dependent: :destroy

  scope :ordered, -> { order(:label) }
  validates :label, presence: true,
                    format: { with: /\A[a-z_]+\z/ }
  validates :char_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :default_value, length: { maximum: ->(block) { block.char_limit } }
  validates :read_only, inclusion: { in: [true, false] }

  # Renders this block as XML for injection into the LLM system prompt.
  # Pass the user-specific +value+ (from AgentMemoryBlock); falls back to
  # +default_value+ if omitted (e.g. in tests or admin previews).
  def render_xml(value: default_value)
    current_chars = value.to_s.length
    <<~XML.strip
      <#{label}>
        <description>#{CGI.escapeHTML(description.to_s)}</description>
        <metadata>
          - chars_current=#{current_chars}
          - chars_limit=#{char_limit}
        </metadata>
        <value>#{CGI.escapeHTML(value.to_s)}</value>
      </#{label}>
    XML
  end

  def chars_remaining
    char_limit - default_value.to_s.length
  end
end
