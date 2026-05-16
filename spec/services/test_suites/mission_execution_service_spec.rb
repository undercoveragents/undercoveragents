# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::MissionExecutionService do
  let(:mission) { create(:mission, flow_data: { "nodes" => [], "edges" => [] }) }
  let(:test_suite) { create(:test_suite, :mission_suite, :with_test_cases, mission:) }
  let(:run) { TestSuites::CreateRunService.call(test_suite) }
  let(:mission_run) { create(:mission_run, mission:, status: "completed", variables: { "result" => "ok" }) }

  let(:mock_runner) { instance_double(Missions::Runner) }

  before do
    allow(Missions::Runner).to receive(:new).and_return(mock_runner)
    allow(mock_runner).to receive(:execute).and_return(mission_run)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Rails.logger).to receive(:error)
  end

  describe ".call" do
    it "marks run as running then completed" do
      described_class.call(run)
      run.reload

      expect(run).to be_completed
      expect(run.started_at).to be_present
      expect(run.completed_at).to be_present
      expect(run.duration_ms).to be_present
    end

    it "preserves started_at when the run is already running" do
      existing_started_at = 5.seconds.ago.change(usec: 0)
      run.update!(status: :running, started_at: existing_started_at)

      described_class.call(run)

      expect(run.reload.started_at.change(usec: 0)).to eq(existing_started_at)
      expect(run).to be_completed
    end

    it "executes all test cases against the mission" do
      described_class.call(run)

      run.test_case_results.reload.each do |result|
        expect(result.actual_status).to eq("completed")
        expect(result.actual_variables).to eq({ "result" => "ok" })
        expect(result.mission_run).to eq(mission_run)
        expect(result.duration_ms).to be_present
      end
    end

    it "broadcasts turbo stream updates" do
      described_class.call(run)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).at_least(:once)
    end

    context "when all assertions pass" do
      let(:test_suite) do
        suite = create(:test_suite, :mission_suite, mission:)
        create(:test_case, :mission_case, test_suite: suite,
                                          expected_status: "completed", expected_variables: {},)
        suite
      end

      it "marks results as passed" do
        described_class.call(run)
        result = run.test_case_results.reload.first

        expect(result).to be_passed
      end
    end

    context "when assertion fails" do
      let(:test_suite) do
        suite = create(:test_suite, :mission_suite, mission:)
        create(:test_case, :mission_case, test_suite: suite,
                                          expected_status: "failed", expected_variables: {},)
        suite
      end

      it "marks results as failed" do
        described_class.call(run)
        result = run.test_case_results.reload.first

        expect(result).to be_failed
        expect(result.analysis).to include("Status mismatch")
      end
    end

    context "when an error occurs during execution" do
      before do
        allow(mock_runner).to receive(:execute).and_raise(StandardError, "Connection failed")
      end

      it "marks the result as error" do
        described_class.call(run)
        result = run.test_case_results.reload.first

        expect(result).to be_error
        expect(result.analysis).to include("Connection failed")
      end
    end

    context "when the entire run fails" do
      before do
        allow(run).to receive(:update!).and_call_original
        allow(run).to receive(:update!).with(hash_including(status: :running)).and_raise(StandardError, "DB error")
      end

      it "marks the run as failed" do
        described_class.call(run)
        run.reload

        expect(run).to be_failed
      end

      it "marks unfinished results as errors and recomputes counts" do
        allow(run).to receive(:update!).and_call_original
        allow(run).to receive(:update!).with(hash_including(status: :running)).and_call_original
        allow_any_instance_of(described_class).to receive(:execute_all_test_cases) do # rubocop:disable RSpec/AnyInstance
          results = run.test_case_results.reorder(nil).to_a
          results.first.update!(status: :passed, passed: true, completed_at: Time.current)
          results.second.update!(status: :running, started_at: Time.current)
          raise StandardError, "forced fail"
        end

        described_class.call(run)
        run.reload

        expect(run).to be_failed
        expect(run.passed_count).to eq(1)
        expect(run.failed_count).to eq(0)
        expect(run.error_count).to eq(run.total_count - 1)
        expect(run.test_case_results.reload.count(&:error?)).to eq(run.total_count - 1)
      end
    end

    context "when run is cancelled mid-execution" do
      before do
        call_count = 0
        allow(mock_runner).to receive(:execute) do
          call_count += 1
          run.update!(status: :cancelled) if call_count == 1
          mission_run
        end
      end

      it "stops processing remaining test cases" do
        described_class.call(run)

        completed_results = run.test_case_results.reload.reject { |r| r.status == "pending" }
        expect(completed_results.size).to be < test_suite.test_cases.count
      end
    end
  end
end
