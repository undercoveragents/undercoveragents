# frozen_string_literal: true

class AutomationTriggerSchedulerJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    loop do
      due_ids = AutomationTrigger.due_schedule.order(:next_run_at, :id).limit(BATCH_SIZE).pluck(:id)
      break if due_ids.empty?

      due_ids.each { |trigger_id| dispatch_due_trigger(trigger_id) }
      break if due_ids.size < BATCH_SIZE
    end
  end

  private

  def dispatch_due_trigger(trigger_id)
    trigger = claim_due_trigger(trigger_id)
    return unless trigger

    AutomationTriggers::Dispatcher.new(
      automation_trigger: trigger,
      payload: trigger.payload,
      source: :schedule,
    ).call
  rescue StandardError => e
    record_dispatch_error(trigger_id, trigger, e)
  end

  def claim_due_trigger(trigger_id)
    trigger = nil
    dispatchable = false
    now = Time.current

    AutomationTrigger.transaction do
      trigger = AutomationTrigger.lock("FOR UPDATE SKIP LOCKED").find_by(id: trigger_id)
      next unless trigger&.due_for_dispatch?(at: now)

      trigger.advance_next_run_at!(from: trigger.next_run_at || now, cutoff: now)
      trigger.last_error = nil
      trigger.save!
      dispatchable = true
    end

    dispatchable ? trigger : nil
  end

  def record_dispatch_error(trigger_id, trigger, error)
    trigger&.update(last_error: error.message)
    Rails.logger.error(
      "[AutomationTriggerSchedulerJob] Failed to dispatch trigger #{trigger_id}: #{error.class} - #{error.message}",
    )
  end
end
