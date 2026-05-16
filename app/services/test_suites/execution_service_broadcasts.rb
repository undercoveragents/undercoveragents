# frozen_string_literal: true

module TestSuites
  module ExecutionServiceBroadcasts
    private

    def broadcast_run_update
      run = @run.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-run-header",
        partial: "admin/test_suite_runs/run_header",
        locals: { run:, test_suite: @test_suite },
      )

      broadcast_status_bar
    end

    def broadcast_result_update(result)
      result.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-result-#{result.id}",
        partial: "admin/test_suite_runs/result_row",
        locals: { result:, test_case: result.test_case, test_suite: @test_suite },
      )

      broadcast_status_bar
    end

    def broadcast_status_bar
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-run-status-bar",
        partial: "admin/test_suite_runs/run_status_bar",
        locals: { run: @run.reload },
      )
    end

    def stream_name
      "test_suite_run_#{@run.id}"
    end
  end
end
