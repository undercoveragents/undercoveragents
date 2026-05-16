# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TestSuiteRuns" do
  let(:agent) { create(:agent) }
  let(:test_suite) { create(:test_suite, :with_test_cases, agent:) }

  describe "GET /test_suite_runs/:id" do
    let(:run) { create(:test_suite_run, :completed, test_suite:) }

    before do
      test_suite.test_cases.each do |tc|
        create(:test_case_result, :passed, test_suite_run: run, test_case: tc)
      end
    end

    it "returns a successful response" do
      get admin_test_suite_test_suite_run_path(test_suite, run)
      expect(response).to have_http_status(:ok)
    end

    it "shows run details" do
      get admin_test_suite_test_suite_run_path(test_suite, run)
      expect(response.body).to include("Completed")
    end

    it "renders turbo stream catch-up updates" do
      get admin_test_suite_test_suite_run_path(test_suite, run, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="test-run-header"')
      expect(response.body).to include('target="test-run-status-bar"')
      expect(response.body).to include('target="test-run-results-body"')
    end

    it "skips header replacement while the run is still active" do
      run.update!(status: :running, started_at: Time.current)

      get admin_test_suite_test_suite_run_path(test_suite, run, format: :turbo_stream)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('target="test-run-header"')
      expect(response.body).to include('target="test-run-status-bar"')
      expect(response.body).to include('target="test-run-results-body"')
    end

    context "with a mission suite" do
      let(:mission_suite) { create(:test_suite, :mission_suite, :with_test_cases) }
      let(:mission_run) { create(:test_suite_run, :completed, test_suite: mission_suite) }

      before do
        mission_suite.test_cases.each do |tc|
          create(:test_case_result, :passed, test_suite_run: mission_run, test_case: tc)
        end
      end

      it "returns a successful response" do
        get admin_test_suite_test_suite_run_path(mission_suite, mission_run)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /test_suite_runs/:id/cancel" do
    context "when run is in progress" do
      let(:run) { create(:test_suite_run, :running, test_suite:) }

      before do
        test_suite.test_cases.each do |tc|
          create(:test_case_result, :pending, test_suite_run: run, test_case: tc)
        end
      end

      it "cancels the run" do
        post cancel_admin_test_suite_test_suite_run_path(test_suite, run)
        expect(run.reload.status).to eq("cancelled")
        expect(run.completed_at).to be_present
      end

      it "marks pending results as error" do
        post cancel_admin_test_suite_test_suite_run_path(test_suite, run)
        run.test_case_results.reload.each do |result|
          expect(result.status).to eq("error")
        end
      end

      it "redirects to the run page" do
        post cancel_admin_test_suite_test_suite_run_path(test_suite, run)
        expect(response).to redirect_to(
          admin_test_suite_test_suite_run_path(test_suite, run),
        )
        expect(flash[:notice]).to eq(I18n.t("test_suite_runs.cancelled"))
      end
    end

    context "when run is already completed" do
      let(:run) { create(:test_suite_run, :completed, test_suite:) }

      it "does not change status" do
        post cancel_admin_test_suite_test_suite_run_path(test_suite, run)
        expect(run.reload.status).to eq("completed")
      end

      it "redirects with notice" do
        post cancel_admin_test_suite_test_suite_run_path(test_suite, run)
        expect(response).to redirect_to(
          admin_test_suite_test_suite_run_path(test_suite, run),
        )
      end
    end
  end
end
