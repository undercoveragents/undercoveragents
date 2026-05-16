# frozen_string_literal: true

# == Schema Information
#
# Table name: test_suite_runs
# Database name: primary
#
#  id             :bigint           not null, primary key
#  completed_at   :datetime
#  debug_snapshot :jsonb            not null
#  duration_ms    :integer
#  error_count    :integer          default(0), not null
#  failed_count   :integer          default(0), not null
#  passed_count   :integer          default(0), not null
#  started_at     :datetime
#  status         :string           default("pending"), not null
#  total_count    :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  test_suite_id  :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_test_suite_runs_on_status                        (status)
#  index_test_suite_runs_on_test_suite_id                 (test_suite_id)
#  index_test_suite_runs_on_test_suite_id_and_created_at  (test_suite_id,created_at)
#  index_test_suite_runs_on_user_id                       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (test_suite_id => test_suites.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe TestSuiteRun do
  describe "factory" do
    it "has a valid factory" do
      expect(build(:test_suite_run)).to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:test_suite).inverse_of(:test_suite_runs) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:test_case_results).dependent(:destroy).inverse_of(:test_suite_run) }
  end

  describe "validations" do
    subject(:run) { build(:test_suite_run) }

    it { is_expected.to validate_numericality_of(:passed_count).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:failed_count).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:error_count).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:total_count).only_integer.is_greater_than_or_equal_to(0) }

    it "adds a validation error when debug snapshot is not a hash" do
      run.debug_snapshot = []

      run.send(:debug_snapshot_must_be_hash)

      expect(run.errors[:debug_snapshot]).to include("must be a JSON object")
    end

    it "normalizes invalid debug snapshot before validation" do
      run.debug_snapshot = []

      run.valid?

      expect(run.debug_snapshot).to eq({})
    end
  end

  describe "enums" do
    subject(:test_suite_run) { build(:test_suite_run) }

    it do
      expect(test_suite_run).to define_enum_for(:status)
        .with_values(
          pending: "pending",
          running: "running",
          evaluating: "evaluating",
          completed: "completed",
          failed: "failed",
          cancelled: "cancelled",
        )
        .backed_by_column_of_type(:string)
        .with_default(:pending)
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at desc" do
        older = create(:test_suite_run, created_at: 2.days.ago)
        newer = create(:test_suite_run, created_at: 1.day.ago)

        expect(described_class.recent).to eq([newer, older])
      end
    end
  end

  describe "#progress_percentage" do
    it "returns 0 when total_count is zero" do
      run = build(:test_suite_run, total_count: 0)
      expect(run.progress_percentage).to eq(0)
    end

    it "returns completion percentage based on finished results" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 4)

      create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.first, status: :passed)
      create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.second, status: :failed)
      create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.third, status: :running)

      expect(run.progress_percentage).to eq(50)
    end
  end

  describe "#pass_rate" do
    it "returns 0.0 when total_count is zero" do
      run = build(:test_suite_run, total_count: 0)
      expect(run.pass_rate).to eq(0.0)
    end

    it "returns passed percentage rounded to 1 decimal" do
      run = build(:test_suite_run, total_count: 10, passed_count: 8)
      expect(run.pass_rate).to eq(80.0)
    end
  end

  describe "#in_progress?" do
    it "is true when running" do
      run = build(:test_suite_run, status: :running)
      expect(run.in_progress?).to be(true)
    end

    it "is true when evaluating" do
      run = build(:test_suite_run, status: :evaluating)
      expect(run.in_progress?).to be(true)
    end

    it "is false otherwise" do
      run = build(:test_suite_run, status: :completed)
      expect(run.in_progress?).to be(false)
    end
  end

  describe "#cancel!" do
    it "cancels an in-progress run and marks unfinished results as error", :aggregate_failures do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)
      result1 = create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.first, status: :pending)
      result2 = create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.second, status: :running)
      result3 = create(:test_case_result, test_suite_run: run, test_case: suite.test_cases.third, status: :passed)

      result = run.cancel!

      expect(result).to be(true)
      expect(run.reload).to be_cancelled
      expect(run.completed_at).to be_present
      expect(result1.reload).to be_error
      expect(result2.reload).to be_error
      expect(result3.reload).to be_passed
    end

    it "returns false if not in progress" do
      run = create(:test_suite_run, :completed)
      expect(run.cancel!).to be(false)
    end
  end

  describe "token aggregations" do
    let(:suite) { create(:test_suite, :with_test_cases) }
    let(:run) { create(:test_suite_run, :completed, test_suite: suite, total_count: suite.test_cases.count) }
    let(:model_record) do
      create(:model, pricing: model_pricing(input_per_million: "3.00", output_per_million: "15.00"))
    end

    before do
      suite.test_cases.each do |tc|
        create_result_with_evaluator_usage(run:, test_case: tc, model_record:)
      end
    end

    it "sums total input tokens across direct and evaluator chats" do
      expect(run.total_input_tokens).to eq(3_000_000)
    end

    it "sums total output tokens across direct and evaluator chats" do
      expect(run.total_output_tokens).to eq(3_000_000)
    end

    it "sums agent input tokens only from test chats" do
      expect(run.agent_input_tokens).to eq(3_000_000)
    end

    it "sums agent output tokens only from test chats" do
      expect(run.agent_output_tokens).to eq(0)
    end

    it "sums evaluator input tokens only from system chats" do
      expect(run.evaluator_input_tokens).to eq(0)
    end

    it "sums evaluator output tokens only from system chats" do
      expect(run.evaluator_output_tokens).to eq(3_000_000)
    end

    it "calculates total tokens from input + output" do
      expect(run.total_tokens).to eq(6_000_000)
    end

    it "sums costs from all test case results" do
      expect(run.calculate_cost).to eq(BigDecimal("54.0"))
    end

    def create_result_with_evaluator_usage(run:, test_case:, model_record:)
      chat = create(:chat, :test_context, model: model_record)
      evaluator_chat = create(:chat, :system_context, parent_chat: chat, model: model_record)
      create(:test_case_result, test_suite_run: run, test_case:, chat:)
      create(:message, chat:, model: model_record,
                       input_tokens: 1_000_000, output_tokens: 0,
                       cached_tokens: 0, cache_creation_tokens: 0,)
      create(:message, chat: evaluator_chat, model: model_record,
                       input_tokens: 0, output_tokens: 1_000_000,
                       cached_tokens: 0, cache_creation_tokens: 0,)
    end
  end

  describe "#compute_counts!" do
    it "keeps passed, failed, and error counts mutually exclusive" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)
      results = suite.test_cases.map { |tc| create(:test_case_result, test_suite_run: run, test_case: tc) }

      results[0].update!(passed: true, status: :passed)
      results[1].update!(passed: false, status: :failed)
      results[2].update!(status: :error, passed: false)

      run.compute_counts!
      run.reload

      expect(run.passed_count).to eq(1)
      expect(run.failed_count).to eq(1)
      expect(run.error_count).to eq(1)
      expect(run.passed_count + run.failed_count + run.error_count).to eq(3)
    end
  end

  describe "#total_tokens" do
    it "sums input and output tokens" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)

      suite.test_cases.each do |tc|
        result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: tc)
        create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      end

      expect(run.total_tokens).to eq(450)
    end

    it "includes cached and cache creation tokens in input totals" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 1)
      result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: suite.test_cases.first)

      create(:message,
             chat: result.chat,
             input_tokens: 100,
             output_tokens: 50,
             cached_tokens: 20,
             cache_creation_tokens: 5,)

      expect(run.total_input_tokens).to eq(125)
      expect(run.total_tokens).to eq(175)
    end
  end

  describe "#agent_input_tokens" do
    it "sums agent input tokens from all results" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)

      suite.test_cases.each do |tc|
        result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: tc)
        evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
        create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
        create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)
      end

      expect(run.agent_input_tokens).to eq(300)
    end
  end

  describe "#agent_output_tokens" do
    it "sums agent output tokens from all results" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)

      suite.test_cases.each do |tc|
        result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: tc)
        evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
        create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
        create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)
      end

      expect(run.agent_output_tokens).to eq(150)
    end
  end

  describe "#evaluator_input_tokens" do
    it "sums evaluator input tokens from all results" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)

      suite.test_cases.each do |tc|
        result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: tc)
        evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
        create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
        create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)
      end

      expect(run.evaluator_input_tokens).to eq(600)
    end
  end

  describe "#evaluator_output_tokens" do
    it "sums evaluator output tokens from all results" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :running, test_suite: suite, total_count: 3)

      suite.test_cases.each do |tc|
        result = create(:test_case_result, :with_chat, test_suite_run: run, test_case: tc)
        evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
        create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
        create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)
      end

      expect(run.evaluator_output_tokens).to eq(225)
    end
  end

  describe "#agent_cost" do
    it "sums only agent-side message costs" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :completed, test_suite: suite, total_count: 3)
      model_record = create(:model, pricing: model_pricing(input_per_million: "10.00", output_per_million: "20.00"))

      suite.test_cases.each do |tc|
        chat = create(:chat, :test_context, model: model_record)
        evaluator_chat = create(:chat, :system_context, parent_chat: chat, model: model_record)
        create(:test_case_result, test_suite_run: run, test_case: tc, chat:)
        create(:message, chat:, model: model_record,
                         input_tokens: 1_000_000, output_tokens: 500_000,
                         cached_tokens: 0, cache_creation_tokens: 0,)
        create(:message, chat: evaluator_chat, model: model_record,
                         input_tokens: 2_000_000, output_tokens: 1_000_000,
                         cached_tokens: 0, cache_creation_tokens: 0,)
      end

      expect(run.agent_cost).to eq(BigDecimal("60.0"))
    end
  end

  describe "#evaluator_cost" do
    it "sums only evaluator-side message costs" do
      suite = create(:test_suite, :with_test_cases)
      run = create(:test_suite_run, :completed, test_suite: suite, total_count: 3)
      model_record = create(:model, pricing: model_pricing(input_per_million: "10.00", output_per_million: "20.00"))

      suite.test_cases.each do |tc|
        chat = create(:chat, :test_context, model: model_record)
        evaluator_chat = create(:chat, :system_context, parent_chat: chat, model: model_record)
        create(:test_case_result, test_suite_run: run, test_case: tc, chat:)
        create(:message, chat:, model: model_record,
                         input_tokens: 1_000_000, output_tokens: 500_000,
                         cached_tokens: 0, cache_creation_tokens: 0,)
        create(:message, chat: evaluator_chat, model: model_record,
                         input_tokens: 2_000_000, output_tokens: 1_000_000,
                         cached_tokens: 0, cache_creation_tokens: 0,)
      end

      expect(run.evaluator_cost).to eq(BigDecimal("120.0"))
    end
  end

  def model_pricing(input_per_million:, output_per_million:)
    {
      "text_tokens" => {
        "standard" => {
          "input_per_million" => input_per_million,
          "output_per_million" => output_per_million,
          "cached_input_per_million" => "0",
          "cache_creation_per_million" => "0",
        },
      },
    }
  end
end
