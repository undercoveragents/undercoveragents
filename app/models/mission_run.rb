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
class MissionRun < ApplicationRecord
  enum :status, {
    pending: "pending",
    running: "running",
    paused: "paused",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled",
  }, validate: true

  has_many_attached :files
  belongs_to :mission
  belongs_to :api_client, optional: true
  belongs_to :channel, optional: true
  belongs_to :channel_target, optional: true
  belongs_to :channel_conversation, optional: true

  scope :active, -> { where(status: [:pending, :running, :paused]) }
  scope :finished, -> { where(status: [:completed, :failed, :cancelled]) }
  scope :recent, -> { order(created_at: :desc) }
  validates :status, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    ["id", "status", "mission_id", "created_at", "started_at", "completed_at", "error"]
  end

  def self.ransackable_associations(_auth_object = nil)
    ["mission"]
  end

  def finished?
    completed? || failed? || cancelled?
  end

  def active?
    pending? || running? || paused?
  end

  def duration
    return nil unless started_at

    (completed_at || Time.current) - started_at
  end

  def flow_snapshot=(value)
    super(Missions::FlowDataSanitizer.parse_and_sanitize(value))
  end

  def node_executions
    (execution_state["execution_log"] || []).map do |entry|
      Missions::NodeExecution.new(
        node_id: entry["node_id"],
        node_type: entry["node_type"],
        status: entry["status"]&.to_sym,
        input: entry["input"],
        output: entry["output"],
        next_port: entry["next_port"],
        started_at: entry["started_at"] ? Time.iso8601(entry["started_at"]) : nil,
        finished_at: entry["finished_at"] ? Time.iso8601(entry["finished_at"]) : nil,
        error: entry["error"],
      )
    end
  end
end
