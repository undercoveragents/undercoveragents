# frozen_string_literal: true

module Api
  class MissionExecutionJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(run_id, tenant_id: nil)
      run = find_run(run_id, tenant_id:)
      return unless run

      mission = run.mission

      runner = Missions::Runner.new(mission)
      runner.resume_or_execute(run, variables: {}, trigger_data: run.trigger_data)

      run.reload
      deliver_callback(run, tenant_id:) if run.callback_url.present?
    end

    private

    def deliver_callback(run, tenant_id: nil)
      Api::CallbackDeliveryJob.perform_later(
        run.id,
        tenant_id: tenant_id.presence || run.mission.operation.tenant_id,
      )
    end

    def find_run(run_id, tenant_id: nil)
      scope = MissionRun
      return scope.find_by(id: run_id) if tenant_id.blank?

      scope.joins(mission: :operation).find_by(id: run_id, operations: { tenant_id: })
    end
  end
end
