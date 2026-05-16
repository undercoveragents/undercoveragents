# frozen_string_literal: true

module TestSuites
  class MissionExecutionService
    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
      @test_suite = run.test_suite
      @mission = @test_suite.mission
    end

    def call
      start_run!
      execute_all_test_cases
      complete_run!
    rescue StandardError => e
      Rails.logger.error "[TestSuites::MissionExecutionService] Run ##{@run.id} failed: #{e.message}"
      fail_run!(e)
    end

    private

    def start_run!
      unless @run.running? && @run.started_at.present?
        @run.update!(status: :running, started_at: @run.started_at || Time.current)
      end

      broadcast_run_update
    end

    def execute_all_test_cases
      results = @run.test_case_results.includes(:test_case).to_a

      results.each do |result|
        break if @run.reload.cancelled?

        process_test_case(result)
      end
    end

    def process_test_case(result)
      test_case = result.test_case

      result.update!(status: :running, started_at: Time.current)
      broadcast_result_update(result)

      mission_run, elapsed_ms = execute_mission(test_case)
      assertion = TestSuites::MissionAssertionService.call(test_case:, mission_run:)

      store_result(result, mission_run:, assertion:, elapsed_ms:)
      broadcast_result_update(result)
    rescue StandardError => e
      handle_test_case_error(result, e)
    end

    def execute_mission(test_case)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      runner = Missions::Runner.new(@mission)
      mission_run = runner.execute(
        variables: test_case.input_variables.dup,
        trigger_data: test_case.input_variables.dup,
      )

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      [mission_run, elapsed_ms]
    end

    def store_result(result, mission_run:, assertion:, elapsed_ms:)
      result.update!(
        mission_run:,
        actual_status: mission_run.status,
        actual_variables: mission_run.variables || {},
        passed: assertion[:passed],
        analysis: assertion[:analysis],
        status: assertion[:passed] ? :passed : :failed,
        duration_ms: elapsed_ms,
        completed_at: Time.current,
      )
    end

    def handle_test_case_error(result, error)
      Rails.logger.error(
        "[TestSuites::MissionExecutionService] Test case ##{result.test_case_id} error: #{error.message}",
      )
      result.update!(
        status: :error,
        analysis: "Error: #{error.message}",
        completed_at: Time.current,
      )
      broadcast_result_update(result)
    end

    def complete_run!
      @run.reload
      return if @run.cancelled?

      @run.compute_counts!
      duration = ((Time.current - @run.started_at) * 1000).round
      @run.update!(status: :completed, completed_at: Time.current, duration_ms: duration)
      broadcast_run_update
    end

    def fail_run!(error)
      @run.update!(status: :failed, completed_at: Time.current)

      @run.test_case_results.where(status: [:pending, :running, :evaluating]).find_each do |result|
        result.update!(
          status: :error,
          analysis: "Run failed: #{error.message}",
          completed_at: Time.current,
        )
        broadcast_result_update(result)
      end

      @run.compute_counts!

      Rails.logger.error "[TestSuites::MissionExecutionService] Run ##{@run.id} failed: #{error.message}"
      broadcast_run_update
    end

    def broadcast_run_update
      @run.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-run-header",
        partial: "admin/test_suite_runs/run_header",
        locals: { run: @run, test_suite: @test_suite },
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-run-status-bar",
        partial: "admin/test_suite_runs/run_status_bar",
        locals: { run: @run },
      )
    end

    def broadcast_result_update(result)
      result.reload

      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name,
        target: "test-result-#{result.id}",
        partial: "admin/test_suite_runs/result_row",
        locals: { result:, test_case: result.test_case, test_suite: @test_suite },
      )
      broadcast_run_update
    end

    def stream_name
      "test_suite_run_#{@run.id}"
    end
  end
end
