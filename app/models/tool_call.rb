# frozen_string_literal: true

# == Schema Information
#
# Table name: tool_calls
# Database name: primary
#
#  id                :bigint           not null, primary key
#  arguments         :jsonb
#  display_name      :string
#  duration_ms       :integer
#  icon              :string
#  name              :string           not null
#  thought_signature :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  message_id        :bigint           not null
#  tool_call_id      :string           not null
#
# Indexes
#
#  index_tool_calls_on_message_id    (message_id)
#  index_tool_calls_on_name          (name)
#  index_tool_calls_on_tool_call_id  (tool_call_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#
class ToolCall < ApplicationRecord
  acts_as_tool_call

  before_validation :apply_display_metadata

  def resolved_display_metadata
    ToolCalls::DisplayMetadataResolver.resolve(name, chat: message&.chat)
  end

  def sync_display_metadata!
    metadata = resolved_display_metadata
    updates = {}
    updates[:display_name] = metadata.display_name if display_name.blank?
    updates[:icon] = metadata.icon if icon.blank?
    return if updates.empty?

    assign_attributes(updates)
    save!
  end

  private

  def apply_display_metadata
    metadata = resolved_display_metadata
    self.display_name = metadata.display_name if display_name.blank?
    self.icon = metadata.icon if icon.blank?
  end
end
