# frozen_string_literal: true

module Missions
  module DebugRunnerStatusBroadcasts
    private

    def broadcast_run_status(run, status, error: nil)
      run.reload if run.persisted?
      duration_ms = run.duration ? (run.duration * 1000).round(1) : nil

      broadcast_run_controls(run, status)
      broadcast_run_status_badge(run, status, error:, duration_ms:)
      broadcast_past_run_entry(run)
    end

    def broadcast_run_controls(run, status)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(run),
        target: "mission-run-controls",
        partial: "admin/missions/debug/run_controls",
        locals: { run_status: status },
      )
    end

    def broadcast_run_status_badge(run, status, error:, duration_ms:)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(run),
        target: "mission-run-status",
        partial: "admin/missions/debug/run_status",
        locals: { run_status: status, run_error: error, run_duration: duration_ms },
      )
    end

    def broadcast_past_run_entry(run)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(run),
        target: "mission-past-run-#{run.id}",
        partial: "admin/missions/debug/past_run_entry",
        locals: { run:, active_run_id: run.id },
      )
    end
  end
end
