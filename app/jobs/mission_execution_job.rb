# frozen_string_literal: true

# Executes a mission in the background using the DebugRunner,
# broadcasting real-time events to the designer via Turbo Streams.
class MissionExecutionJob < ApplicationJob
  queue_as :default

  # Don't retry failed executions — the run record captures the error.
  discard_on StandardError

  def perform(run_id, tenant_id: nil, variables: {}, trigger_data: {})
    run = find_run(run_id, tenant_id:)
    unless run
      Rails.logger.error(
        "[MissionExecutionJob] MissionRun #{run_id} not found#{tenant_scope_log_suffix(tenant_id)}, skipping",
      )
      return
    end

    mission = run.mission
    runner = Missions::DebugRunner.new(mission)
    runner.resume_or_execute(run, variables:, trigger_data:)
  rescue StandardError => e
    # Ensure the run is ALWAYS marked as failed, even if the runner's own
    # error handling didn't catch it (e.g., broadcast failure, serialization error).
    Rails.logger.error("[MissionExecutionJob] Unhandled error for run #{run_id}: #{e.class} — #{e.message}")
    safely_fail_run(run_id, e)
  end

  private

  def find_run(run_id, tenant_id: nil)
    scope = MissionRun
    return scope.find_by(id: run_id) if tenant_id.blank?

    scope.joins(mission: :operation).find_by(id: run_id, operations: { tenant_id: })
  end

  def tenant_scope_log_suffix(tenant_id)
    return "" if tenant_id.blank?

    " for tenant #{tenant_id}"
  end

  def safely_fail_run(run_id, error)
    updated = MissionRun.where(id: run_id, status: [:pending, :running, :paused]).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: "failed",
      error: "Execution error: #{error.message}",
      completed_at: Time.current,
    )
    return if updated.zero?

    # Best-effort broadcast so the UI updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "#{Missions::DebugRunner::STREAM_PREFIX}_#{run_id}",
      target: "mission-run-controls",
      partial: "admin/missions/debug/run_controls",
      locals: { run_status: "failed" },
    )
    Turbo::StreamsChannel.broadcast_replace_to(
      "#{Missions::DebugRunner::STREAM_PREFIX}_#{run_id}",
      target: "mission-run-status",
      partial: "admin/missions/debug/run_status",
      locals: { run_status: "failed", run_error: error.message },
    )
  rescue StandardError => e
    Rails.logger.error("[MissionExecutionJob] Failed to broadcast failure for run #{run_id}: #{e.message}")
  end
end
