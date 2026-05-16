# frozen_string_literal: true

# == Schema Information
#
# Table name: chats
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  child_chats_count       :integer          default(0), not null
#  execution_context       :string           default("playground"), not null
#  messages_count          :integer          default(0), not null
#  status                  :string           default("idle"), not null
#  title                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  agent_id                :bigint
#  channel_conversation_id :bigint
#  channel_id              :bigint
#  channel_target_id       :bigint
#  client_id               :bigint
#  mission_id              :bigint
#  model_id                :bigint
#  parent_chat_id          :bigint
#  telegram_chat_id        :bigint
#  user_id                 :bigint
#
# Indexes
#
#  index_chats_on_agent_id                 (agent_id)
#  index_chats_on_channel_conversation_id  (channel_conversation_id)
#  index_chats_on_channel_id               (channel_id)
#  index_chats_on_channel_target_id        (channel_target_id)
#  index_chats_on_client_id                (client_id)
#  index_chats_on_execution_context        (execution_context)
#  index_chats_on_mission_id               (mission_id)
#  index_chats_on_model_id                 (model_id)
#  index_chats_on_parent_chat_id           (parent_chat_id)
#  index_chats_on_telegram_chat_id         (telegram_chat_id)
#  index_chats_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (channel_conversation_id => channel_conversations.id)
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (client_id => clients.id)
#  fk_rails_...  (mission_id => missions.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (parent_chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :chat do
    model

    trait :with_parent do
      parent_chat factory: :chat
    end

    trait :with_agent do
      agent
    end

    trait :streaming do
      status { "streaming" }
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :playground_context do
      execution_context { "playground" }
    end

    trait :application_context do
      execution_context { "application" }
    end

    trait :test_context do
      execution_context { "test" }
    end

    trait :system_context do
      execution_context { "system" }
    end

    trait :user_context do
      execution_context { "user" }
    end

    trait :channel_context do
      execution_context { "channel" }
    end
  end
end
