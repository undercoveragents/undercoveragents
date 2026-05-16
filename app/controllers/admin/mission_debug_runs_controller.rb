# frozen_string_literal: true

module Admin
  class MissionDebugRunsController < BaseController
    include MissionRecordContext

    before_action :set_mission

    # GET /admin/missions/:id/debug_inputs — re-renders the debug variable inputs panel
    def debug_inputs
      render partial: "admin/missions/debug/inputs", locals: { mission: @mission }, layout: false
    end

    # POST /admin/missions/:id/execute_debug — start a debug run (async)
    def execute_debug
      launch = build_debug_launch.call
      @run = launch.run
      enqueue_debug_run(launch)

      respond_to do |format|
        format.turbo_stream { render template: "admin/missions/execute_debug" }
        format.json do
          render json: {
            run_id: @run.id,
            status: "pending",
            stream: "#{Missions::DebugRunner::STREAM_PREFIX}_#{@run.id}",
          }
        end
      end
    end

    # GET /admin/missions/:id/run_status — get current run state
    def run_status
      run = @mission.mission_runs.recent.first
      render json: run ? debug_state_for(run).status_payload : { status: "none" }
    end

    # GET /admin/missions/:id/run_catch_up — full rendered state for catch-up (turbo_stream)
    def run_catch_up
      @run = @mission.mission_runs.recent.first
      return head(:no_content) unless @run

      @debug_state = debug_state_for(@run)
      render template: "admin/missions/run_catch_up"
    end

    # POST /admin/missions/:id/cancel_run — cancel active run
    def cancel_run
      run = @mission.mission_runs.active.recent.first
      return render_no_active_run unless run

      Missions::Runner.new(@mission).cancel(run)
      render_cancelled_run
    end

    # GET /admin/missions/:id/load_debug_run — load a specific run's state into the debug panel
    def load_debug_run
      @run = @mission.mission_runs.find(params.expect(:run_id))
      @debug_state = debug_state_for(@run)
      @recent_runs = recent_runs
      render template: "admin/missions/load_debug_run"
    end

    # POST /admin/missions/:id/reset_debug — clear debug state
    def reset_debug
      @recent_runs = recent_runs
      render template: "admin/missions/reset_debug"
    end

    private

    def debug_state_for(run)
      Missions::DebugRunState.new(mission: @mission, run:)
    end

    def recent_runs
      @mission.mission_runs.recent.limit(10)
    end

    def build_debug_launch
      Missions::DebugRunLauncher.new(
        mission: @mission,
        blob_url_resolver: ->(blob) { rails_blob_url(blob, disposition: "attachment") },
        request_data: {
          flow_data: params[:flow_data],
          variables: params[:variables],
          trigger_data: params[:trigger_data],
          trigger_files: params[:trigger_files],
        },
      )
    end

    def enqueue_debug_run(launch)
      MissionExecutionJob.perform_later(
        @run.id,
        tenant_id: @mission.operation.tenant_id,
        variables: launch.variables,
        trigger_data: launch.trigger_data,
      )
    end

    def render_cancelled_run
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "mission-run-controls",
              partial: "admin/missions/debug/run_controls",
              locals: { run_status: "cancelled" },
            ),
            turbo_stream.replace(
              "mission-run-status",
              partial: "admin/missions/debug/run_status",
              locals: { run_status: "cancelled" },
            ),
          ]
        end
        format.json { render json: { status: "cancelled" } }
      end
    end

    def render_no_active_run
      respond_to do |format|
        format.turbo_stream { head :ok }
        format.json { render json: { status: "none" } }
      end
    end
  end
end
