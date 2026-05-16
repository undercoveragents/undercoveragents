# frozen_string_literal: true

class TestSuiteExecutionJob < ApplicationJob
  queue_as :default

  # Discard if the run record has been deleted before the job starts.
  discard_on ActiveRecord::RecordNotFound

  def perform(run_id, tenant_id: nil)
    run = find_run(run_id, tenant_id:)
    unless run
      Rails.logger.error("TestSuiteExecutionJob run #{run_id} not found")
      return
    end

    return if run.cancelled?

    if run.test_suite.mission?
      TestSuites::MissionExecutionService.call(run)
    else
      TestSuites::ExecutionService.call(run)
    end
  rescue StandardError => e
    Rails.logger.error("TestSuiteExecutionJob failed for run #{run_id}: #{e.message}")
    mark_run_failed_if_active(run&.id)
  end

  private

  def find_run(run_id, tenant_id: nil)
    scope = TestSuiteRun
    return scope.find_by(id: run_id) if tenant_id.blank?

    scope.where(test_suite_id: tenant_scoped_test_suites(tenant_id).select(:id)).find_by(id: run_id)
  end

  def tenant_scoped_test_suites(tenant_id)
    TestSuite.where(agent_id: Agent.joins(:operation).where(operations: { tenant_id: }).select(:id))
             .or(TestSuite.where(mission_id: Mission.joins(:operation).where(operations: { tenant_id: }).select(:id)))
  end

  def mark_run_failed_if_active(run_id)
    return unless run_id

    TestSuiteRun.where(id: run_id, status: [:pending, :running, :evaluating]).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: :failed,
      completed_at: Time.current,
    )
  end
end
