# frozen_string_literal: true

# == Schema Information
#
# Table name: automation_triggers
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  cron_expression         :string
#  enabled                 :boolean          default(TRUE), not null
#  last_error              :text
#  last_result_record_type :string
#  last_triggered_at       :datetime
#  name                    :string           not null
#  next_run_at             :datetime
#  payload                 :jsonb            not null
#  schedulable_type        :string           not null
#  timezone                :string           default("UTC"), not null
#  trigger_type            :string           not null
#  webhook_secret_digest   :string
#  webhook_secret_prefix   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  last_result_record_id   :bigint
#  operation_id            :bigint           not null
#  schedulable_id          :bigint           not null
#
# Indexes
#
#  index_automation_triggers_on_last_result_record    (last_result_record_type,last_result_record_id)
#  index_automation_triggers_on_operation_id          (operation_id)
#  index_automation_triggers_on_schedulable           (schedulable_type,schedulable_id)
#  index_automation_triggers_on_schedulable_and_name  (schedulable_type,schedulable_id,name) UNIQUE
#  index_automation_triggers_on_schedule_state        (trigger_type,enabled,next_run_at)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class MissionTrigger < AutomationTrigger
  WEBHOOK_SECRET_PREFIX = "mtw_"

  alias_attribute :mission_id, :schedulable_id
  alias_attribute :last_mission_run_id, :last_result_record_id

  belongs_to :mission,
             class_name: "Mission",
             foreign_key: :schedulable_id,
             inverse_of: :mission_triggers,
             optional: false
  belongs_to :last_mission_run,
             class_name: "MissionRun",
             foreign_key: :last_result_record_id,
             inverse_of: false,
             optional: true

  default_scope { where(schedulable_type: "Mission") }

  validates :name, uniqueness: { scope: :mission_id, case_sensitive: false }

  before_validation :sync_mission_compatibility_state

  def self.generate_webhook_secret
    raw = SecureRandom.hex(WEBHOOK_SECRET_BYTE_LENGTH)
    raw_secret = "#{WEBHOOK_SECRET_PREFIX}#{raw}"

    {
      raw_secret:,
      prefix: "#{WEBHOOK_SECRET_PREFIX}#{raw[0, 8]}",
      digest: Digest::SHA256.hexdigest(raw_secret),
    }
  end

  def mission=(record)
    self.schedulable = record
    self.operation = record&.operation
    super
  end

  def last_mission_run=(record)
    self.last_result_record = record
    super
  end

  private

  def sync_mission_compatibility_state
    self.schedulable = mission if mission.present?
    self.schedulable_type = "Mission" if schedulable_type.blank? || mission.present?
  end
end
