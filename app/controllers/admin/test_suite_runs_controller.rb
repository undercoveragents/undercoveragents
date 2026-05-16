# frozen_string_literal: true

module Admin
  class TestSuiteRunsController < BaseController
    before_action :set_test_suite
    before_action :set_run, only: [:show, :cancel]

    def show
      load_run_details

      return unless request.format.turbo_stream? && params[:format] == "turbo_stream"

      render turbo_stream: turbo_stream_updates
    end

    def cancel
      @run.cancel!

      redirect_to admin_test_suite_test_suite_run_path(@test_suite, @run),
                  notice: t("test_suite_runs.cancelled")
    end

    private

    def set_test_suite
      @test_suite = tenant_scoped_test_suites.friendly.find(params.expect(:test_suite_id))
    end

    def set_run
      @run = @test_suite.test_suite_runs.find(params.expect(:id))
    end

    def load_run_details
      @total_cost = @test_suite.agent? && @run.completed? ? @run.calculate_cost : 0
      @test_case_results = @run.test_case_results.includes(:test_case).ordered
    end

    def turbo_stream_updates
      updates = []
      updates << turbo_stream_header_update unless @run.in_progress?
      updates.push(turbo_stream_status_bar_update, turbo_stream_results_body_update)
      updates
    end

    def turbo_stream_header_update
      turbo_stream.replace(
        "test-run-header",
        partial: "admin/test_suite_runs/run_header",
        locals: { run: @run, test_suite: @test_suite, total_cost: @total_cost },
      )
    end

    def turbo_stream_status_bar_update
      turbo_stream.replace(
        "test-run-status-bar",
        partial: "admin/test_suite_runs/run_status_bar",
        locals: { run: @run },
      )
    end

    def turbo_stream_results_body_update
      turbo_stream.replace(
        "test-run-results-body",
        partial: "admin/test_suite_runs/results_body",
        locals: { test_case_results: @test_case_results, test_suite: @test_suite },
      )
    end
  end
end
