# frozen_string_literal: true

# == Schema Information
#
# Table name: mission_runs
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  callback_url            :string
#  completed_at            :datetime
#  error                   :text
#  execution_state         :jsonb            not null
#  flow_snapshot           :jsonb            not null
#  started_at              :datetime
#  status                  :string           default("pending"), not null
#  trigger_data            :jsonb            not null
#  variables               :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  api_client_id           :bigint
#  channel_conversation_id :bigint
#  channel_id              :bigint
#  channel_target_id       :bigint
#  current_node_id         :string
#  mission_id              :bigint           not null
#
# Indexes
#
#  index_mission_runs_on_api_client_id            (api_client_id)
#  index_mission_runs_on_channel_conversation_id  (channel_conversation_id)
#  index_mission_runs_on_channel_id               (channel_id)
#  index_mission_runs_on_channel_target_id        (channel_target_id)
#  index_mission_runs_on_mission_id               (mission_id)
#  index_mission_runs_on_mission_id_and_status    (mission_id,status)
#  index_mission_runs_on_status                   (status)
#
# Foreign Keys
#
#  fk_rails_...  (api_client_id => api_clients.id)
#  fk_rails_...  (channel_conversation_id => channel_conversations.id)
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (channel_target_id => channel_targets.id)
#  fk_rails_...  (mission_id => missions.id)
#
FactoryBot.define do
  factory :mission_run do
    mission
    status { "pending" }
    flow_snapshot { { "nodes" => [], "edges" => [] } }
    variables { {} }
    execution_state { {} }
    trigger_data { {} }
  end
end
