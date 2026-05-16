# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_conversations
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  metadata                 :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  channel_id               :bigint           not null
#  channel_identity_id      :bigint
#  channel_target_id        :bigint
#  chat_id                  :bigint
#  external_conversation_id :string           not null
#  external_thread_id       :string           default(""), not null
#  mission_run_id           :bigint
#
# Indexes
#
#  index_channel_conversations_on_channel_id           (channel_id)
#  index_channel_conversations_on_channel_identity_id  (channel_identity_id)
#  index_channel_conversations_on_channel_target_id    (channel_target_id)
#  index_channel_conversations_on_chat_id              (chat_id)
#  index_channel_conversations_on_external_ids         (channel_id,external_conversation_id,external_thread_id) UNIQUE
#  index_channel_conversations_on_mission_run_id       (mission_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_identity_id => channel_identities.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (mission_run_id => mission_runs.id)
#
require "rails_helper"

RSpec.describe ChannelConversation do
  describe "validations" do
    let(:tenant) { create(:tenant) }
    let(:operation) { create(:operation, tenant:) }
    let(:channel) { create(:channel, :api, tenant:) }
    let(:agent) { create(:agent, operation:) }
    let(:mission) { create(:mission, operation:) }

    it "accepts conversations without optional linked records" do
      conversation = build(:channel_conversation, metadata: "invalid")

      expect(conversation).to be_valid
      expect(conversation.metadata).to eq({})
    end

    it "normalizes metadata and accepts records from the same channel" do
      agent_target = create(:channel_target, channel:, target: agent, default: true)
      mission_target = create(:channel_target, :mission, channel:, target: mission, position: 1)
      identity = create(:channel_identity, channel:)
      chat = create(:chat, :channel_context, agent:, channel:, channel_target: agent_target)
      mission_run = create(:mission_run, mission:, channel:, channel_target: mission_target)
      conversation = build(
        :channel_conversation,
        channel:,
        channel_target: agent_target,
        channel_identity: identity,
        chat:,
        mission_run:,
        metadata: "invalid",
      )

      expect(conversation).to be_valid
      expect(conversation.metadata).to eq({})
    end

    it "rejects associated records from a different channel" do
      channel.update!(name: "Primary Channel")
      other_channel = create(:channel, :api, tenant:, name: "Other Channel")
      other_target = create(:channel_target, channel: other_channel, target: agent, default: true)
      other_identity = create(:channel_identity, channel: other_channel)
      other_chat = create(:chat, :channel_context, agent:, channel: other_channel, channel_target: other_target)
      other_mission_target = create(:channel_target, :mission, channel: other_channel, target: mission, position: 1)
      other_mission_run = create(:mission_run, mission:, channel: other_channel, channel_target: other_mission_target)
      conversation = build(
        :channel_conversation,
        channel:,
        channel_target: other_target,
        channel_identity: other_identity,
        chat: other_chat,
        mission_run: other_mission_run,
      )

      expect(conversation).not_to be_valid
      expect(conversation.errors[:channel_target]).to include("must belong to the same channel")
      expect(conversation.errors[:channel_identity]).to include("must belong to the same channel")
      expect(conversation.errors[:chat]).to include("must belong to the same channel")
      expect(conversation.errors[:mission_run]).to include("must belong to the same channel")
    end
  end
end
