# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::CreateRunService do
  describe ".call" do
    let(:test_suite) { create(:test_suite, :with_test_cases) }

    it "creates a test suite run" do
      expect { described_class.call(test_suite) }.to change(TestSuiteRun, :count).by(1)
    end

    it "returns the run" do
      run = described_class.call(test_suite)
      expect(run).to be_a(TestSuiteRun)
      expect(run).to be_persisted
    end

    it "sets the run to pending" do
      run = described_class.call(test_suite)
      expect(run).to be_pending
    end

    it "sets total_count to the number of test cases" do
      run = described_class.call(test_suite)
      expect(run.total_count).to eq(test_suite.test_cases.count)
    end

    it "stores the user that started the run" do
      user = create(:user, tenant: test_suite.tenant)

      run = described_class.call(test_suite, user:)

      expect(run.user).to eq(user)
    end

    it "creates a pending result for each test case" do
      run = described_class.call(test_suite)
      expect(run.test_case_results.count).to eq(test_suite.test_cases.count)
      expect(run.test_case_results).to all(be_pending)
    end

    it "creates a run for only the selected test cases" do
      selected_case = test_suite.test_cases.ordered.first

      run = described_class.call(test_suite, test_cases: [selected_case])

      expect(run.total_count).to eq(1)
      expect(run.test_case_results.pluck(:test_case_id)).to eq([selected_case.id])
    end

    it "raises when a selected test case belongs to another suite" do
      foreign_case = create(:test_case, test_suite: create(:test_suite, :with_test_cases))

      expect { described_class.call(test_suite, test_cases: [foreign_case]) }
        .to raise_error(ArgumentError, /All selected test cases must belong/)
    end

    it "associates results with the correct test cases" do
      run = described_class.call(test_suite)
      result_case_ids = run.test_case_results.pluck(:test_case_id).sort
      expected_ids = test_suite.test_cases.pluck(:id).sort
      expect(result_case_ids).to eq(expected_ids)
    end

    context "with no test cases" do
      let(:test_suite) { create(:test_suite) }

      it "creates a run with zero total count" do
        run = described_class.call(test_suite)
        expect(run.total_count).to eq(0)
        expect(run.test_case_results).to be_empty
      end
    end
  end
end
