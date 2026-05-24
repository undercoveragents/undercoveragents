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
FactoryBot.define do
  factory :automation_trigger do
    transient do
      target { association(:mission) }
    end

    schedulable { target }
    schedulable_type { target.class.base_class.name }
    operation { target.operation }
    sequence(:name) { |n| "Trigger #{n}" }
    trigger_type { "schedule" }
    enabled { true }
    cron_expression { "0 * * * *" }
    timezone { "UTC" }
    payload { {} }

    trait :schedule do
      trigger_type { "schedule" }
      cron_expression { "0 * * * *" }
      timezone { "UTC" }
    end

    trait :webhook do
      trigger_type { "webhook" }
      cron_expression { nil }

      after(:build) do |automation_trigger|
        next if automation_trigger.webhook_secret_digest.present? && automation_trigger.webhook_secret_prefix.present?

        secret_data = AutomationTrigger.generate_webhook_secret
        automation_trigger.webhook_secret_prefix = secret_data[:prefix]
        automation_trigger.webhook_secret_digest = secret_data[:digest]
        automation_trigger.instance_variable_set(:@raw_webhook_secret, secret_data[:raw_secret])
      end
    end
  end

  factory :mission_trigger do
    mission
    schedulable { mission }
    schedulable_type { "Mission" }
    operation { mission.operation }
    sequence(:name) { |n| "Trigger #{n}" }
    trigger_type { "schedule" }
    enabled { true }
    cron_expression { "0 * * * *" }
    timezone { "UTC" }
    payload { {} }

    trait :schedule do
      trigger_type { "schedule" }
      cron_expression { "0 * * * *" }
      timezone { "UTC" }
    end

    trait :webhook do
      trigger_type { "webhook" }
      cron_expression { nil }

      after(:build) do |mission_trigger|
        next if mission_trigger.webhook_secret_digest.present? && mission_trigger.webhook_secret_prefix.present?

        secret_data = MissionTrigger.generate_webhook_secret
        mission_trigger.webhook_secret_prefix = secret_data[:prefix]
        mission_trigger.webhook_secret_digest = secret_data[:digest]
        mission_trigger.instance_variable_set(:@raw_webhook_secret, secret_data[:raw_secret])
      end
    end
  end
end
