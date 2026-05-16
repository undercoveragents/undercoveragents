# frozen_string_literal: true

# == Schema Information
#
# Table name: test_case_results
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  actual_answer             :text
#  actual_child_builtin_keys :jsonb            not null
#  actual_status             :string
#  actual_tool_names         :jsonb            not null
#  actual_variables          :jsonb            not null
#  analysis                  :text
#  behavior_analysis         :text
#  behavior_passed           :boolean
#  completed_at              :datetime
#  debug_snapshot            :jsonb            not null
#  duration_ms               :integer
#  passed                    :boolean
#  score                     :float
#  semantic_passed           :boolean
#  started_at                :datetime
#  status                    :string           default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  chat_id                   :bigint
#  mission_run_id            :bigint
#  test_case_id              :bigint           not null
#  test_suite_run_id         :bigint           not null
#
# Indexes
#
#  idx_test_case_results_on_run_and_case         (test_suite_run_id,test_case_id) UNIQUE
#  index_test_case_results_on_chat_id            (chat_id)
#  index_test_case_results_on_mission_run_id     (mission_run_id)
#  index_test_case_results_on_status             (status)
#  index_test_case_results_on_test_case_id       (test_case_id)
#  index_test_case_results_on_test_suite_run_id  (test_suite_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (mission_run_id => mission_runs.id)
#  fk_rails_...  (test_case_id => test_cases.id)
#  fk_rails_...  (test_suite_run_id => test_suite_runs.id)
#
require "rails_helper"

RSpec.describe TestCaseResult do
  subject(:result) { build(:test_case_result) }

  describe "associations" do
    it { is_expected.to belong_to(:test_suite_run).inverse_of(:test_case_results) }
    it { is_expected.to belong_to(:test_case).inverse_of(:test_case_results) }
    it { is_expected.to belong_to(:chat).optional }
  end

  describe "validations" do
    it do
      expect(result).to validate_numericality_of(:score)
        .is_greater_than_or_equal_to(0.0)
        .is_less_than_or_equal_to(1.0)
        .allow_nil
    end

    it "normalizes debug JSON fields" do
      result.actual_tool_names = "list_resources"
      result.actual_child_builtin_keys = "mission_designer"
      result.debug_snapshot = nil
      result.valid?

      expect(result.actual_tool_names).to eq(["list_resources"])
      expect(result.actual_child_builtin_keys).to eq(["mission_designer"])
      expect(result.debug_snapshot).to eq({})
    end

    it "adds validation errors for invalid debug JSON shapes" do
      result.actual_variables = []
      result.actual_tool_names = {}
      result.actual_child_builtin_keys = {}
      result.debug_snapshot = []

      result.send(:debug_json_columns_must_have_expected_shape)

      expect(result.errors.attribute_names).to include(
        :actual_variables,
        :actual_tool_names,
        :actual_child_builtin_keys,
        :debug_snapshot,
      )
    end

    it "normalizes invalid actual variables before validation" do
      result.actual_variables = []

      result.valid?

      expect(result.actual_variables).to eq({})
    end
  end

  describe "enums" do
    it do
      expect(result).to define_enum_for(:status).with_values(
        pending: "pending",
        running: "running",
        evaluating: "evaluating",
        passed: "passed",
        failed: "failed",
        error: "error",
      ).backed_by_column_of_type(:string)
    end
  end

  describe "#completed?" do
    it "returns true for passed" do
      expect(build(:test_case_result, :passed).completed?).to be true
    end

    it "returns true for failed" do
      expect(build(:test_case_result, :failed).completed?).to be true
    end

    it "returns true for error" do
      expect(build(:test_case_result, :error).completed?).to be true
    end

    it "returns false for pending" do
      expect(build(:test_case_result, :pending).completed?).to be false
    end

    it "returns false for running" do
      expect(build(:test_case_result, :running).completed?).to be false
    end
  end

  describe "#duration_seconds" do
    it "returns nil when no duration" do
      expect(build(:test_case_result, duration_ms: nil).duration_seconds).to be_nil
    end

    it "converts ms to seconds" do
      expect(build(:test_case_result, duration_ms: 2500).duration_seconds).to eq(2.5)
    end
  end

  describe "#input_tokens" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).input_tokens).to eq(0)
    end

    it "sums input tokens from test and evaluator chats" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.input_tokens).to eq(300)
    end

    it "includes cached and cache creation tokens in request-side input activity" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message,
             chat: result.chat,
             input_tokens: 100,
             output_tokens: 50,
             cached_tokens: 20,
             cache_creation_tokens: 5,)
      create(:message,
             chat: evaluator_chat,
             input_tokens: 200,
             output_tokens: 75,
             cached_tokens: 10,
             cache_creation_tokens: 0,)

      expect(result.input_tokens).to eq(335)
    end
  end

  describe "#output_tokens" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).output_tokens).to eq(0)
    end

    it "sums output tokens from test and evaluator chats" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.output_tokens).to eq(125)
    end
  end

  describe "#total_tokens" do
    it "sums input and output tokens" do
      result = create(:test_case_result, :with_chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)

      expect(result.total_tokens).to eq(150)
    end
  end

  describe "#calculate_cost" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).calculate_cost).to eq(0)
    end

    it "includes evaluator child chat cost" do
      result = create(:test_case_result, :with_chat)
      model_record = create(:model, pricing: {
                              "text_tokens" => {
                                "standard" => {
                                  "input_per_million" => "3.00",
                                  "output_per_million" => "15.00",
                                  "cached_input_per_million" => "0",
                                  "cache_creation_per_million" => "0",
                                },
                              },
                            },)
      result.chat.update!(model: model_record)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat, model: model_record)

      create(:message, chat: result.chat, model: model_record,
                       input_tokens: 1_000_000, output_tokens: 0,
                       cached_tokens: 0, cache_creation_tokens: 0,)
      create(:message, chat: evaluator_chat, model: model_record,
                       input_tokens: 0, output_tokens: 1_000_000,
                       cached_tokens: 0, cache_creation_tokens: 0,)

      expect(result.calculate_cost).to eq(BigDecimal("18.0"))
    end
  end

  describe "#related_chats" do
    it "returns empty relation when no chat" do
      expect(build(:test_case_result).related_chats).to be_empty
    end

    it "includes the chat and its children" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)

      expect(result.related_chats).to contain_exactly(result.chat, evaluator_chat)
    end
  end

  describe "#related_messages" do
    it "returns empty relation when no chat" do
      expect(build(:test_case_result).related_messages).to be_empty
    end

    it "returns messages from test and evaluator chats" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      msg1 = create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      msg2 = create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.related_messages).to contain_exactly(msg1, msg2)
    end
  end

  describe "#agent_input_tokens" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).agent_input_tokens).to eq(0)
    end

    it "sums input tokens from test context chats only" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.agent_input_tokens).to eq(100)
    end
  end

  describe "#agent_output_tokens" do
    it "sums output tokens from test context chats only" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.agent_output_tokens).to eq(50)
    end
  end

  describe "#evaluator_input_tokens" do
    it "sums input tokens from system context chats only" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.evaluator_input_tokens).to eq(200)
    end
  end

  describe "#evaluator_output_tokens" do
    it "sums output tokens from system context chats only" do
      result = create(:test_case_result, :with_chat)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat)
      create(:message, chat: result.chat, input_tokens: 100, output_tokens: 50)
      create(:message, chat: evaluator_chat, input_tokens: 200, output_tokens: 75)

      expect(result.evaluator_output_tokens).to eq(75)
    end
  end

  describe "#agent_cost" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).agent_cost).to eq(0)
    end

    it "sums cost from test context chats only" do
      result = create(:test_case_result, :with_chat)
      model_record = create(:model, pricing: {
                              "text_tokens" => {
                                "standard" => {
                                  "input_per_million" => "3.00",
                                  "output_per_million" => "15.00",
                                  "cached_input_per_million" => "0",
                                  "cache_creation_per_million" => "0",
                                },
                              },
                            },)
      result.chat.update!(model: model_record)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat, model: model_record)
      create(:message, chat: result.chat, model: model_record,
                       input_tokens: 1_000_000, output_tokens: 0,
                       cached_tokens: 0, cache_creation_tokens: 0,)
      create(:message, chat: evaluator_chat, model: model_record,
                       input_tokens: 0, output_tokens: 1_000_000,
                       cached_tokens: 0, cache_creation_tokens: 0,)

      expect(result.agent_cost).to eq(BigDecimal("3.0"))
    end
  end

  describe "#evaluator_cost" do
    it "returns 0 when no chat" do
      expect(build(:test_case_result).evaluator_cost).to eq(0)
    end

    it "sums cost from system context chats only" do
      result = create(:test_case_result, :with_chat)
      model_record = create(:model, pricing: {
                              "text_tokens" => {
                                "standard" => {
                                  "input_per_million" => "3.00",
                                  "output_per_million" => "15.00",
                                  "cached_input_per_million" => "0",
                                  "cache_creation_per_million" => "0",
                                },
                              },
                            },)
      result.chat.update!(model: model_record)
      evaluator_chat = create(:chat, :system_context, parent_chat: result.chat, model: model_record)
      create(:message, chat: result.chat, model: model_record,
                       input_tokens: 1_000_000, output_tokens: 0,
                       cached_tokens: 0, cache_creation_tokens: 0,)
      create(:message, chat: evaluator_chat, model: model_record,
                       input_tokens: 0, output_tokens: 1_000_000,
                       cached_tokens: 0, cache_creation_tokens: 0,)

      expect(result.evaluator_cost).to eq(BigDecimal("15.0"))
    end
  end

  describe "#node_executions" do
    it "returns empty array when no mission_run" do
      result = build(:test_case_result, mission_run: nil)
      expect(result.node_executions).to eq([])
    end

    it "delegates to mission_run when present" do
      mission_run = instance_double(MissionRun, node_executions: [{ "node_id" => "n1" }])
      result = build(:test_case_result)
      allow(result).to receive(:mission_run).and_return(mission_run)

      expect(result.node_executions).to eq([{ "node_id" => "n1" }])
    end
  end

  describe "#execution_node_count" do
    it "returns count of node executions" do
      result = build(:test_case_result, mission_run: nil)
      allow(result).to receive(:node_executions).and_return([1, 2, 3])

      expect(result.execution_node_count).to eq(3)
    end
  end
end
