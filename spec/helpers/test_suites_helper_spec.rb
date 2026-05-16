# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuitesHelper do
  describe "#test_suite_status_badge" do
    it "returns success badge for active suite" do
      suite = build(:test_suite, status: "active")
      result = helper.test_suite_status_badge(suite)
      expect(result).to include("badge-success")
      expect(result).to include("Active")
    end

    it "returns secondary badge for archived suite" do
      suite = build(:test_suite, status: "archived")
      result = helper.test_suite_status_badge(suite)
      expect(result).to include("badge-secondary")
      expect(result).to include("Archived")
    end
  end

  describe "#test_suite_type_badge" do
    it "returns brand badge for agent suite" do
      suite = build(:test_suite, suite_type: "agent")
      result = helper.test_suite_type_badge(suite)
      expect(result).to include("badge-brand")
      expect(result).to include("Agent")
    end

    it "returns warning badge for mission suite" do
      suite = build(:test_suite, :mission_suite)
      result = helper.test_suite_type_badge(suite)
      expect(result).to include("badge-warning")
      expect(result).to include("Mission")
    end
  end

  describe "#test_case_match_type_badge" do
    it "returns brand badge for exact match" do
      tc = build(:test_case, :exact)
      result = helper.test_case_match_type_badge(tc)
      expect(result).to include("badge-brand")
      expect(result).to include("Exact")
      expect(result).to include("fa-equals")
    end

    it "returns warning badge for semantic match" do
      tc = build(:test_case, :semantic)
      result = helper.test_case_match_type_badge(tc)
      expect(result).to include("badge-warning")
      expect(result).to include("Semantic")
      expect(result).to include("fa-brain")
    end

    it "returns warning badge for partial match" do
      tc = build(:test_case, match_type: "partial")
      result = helper.test_case_match_type_badge(tc)
      expect(result).to include("badge-warning")
      expect(result).to include("Partial")
      expect(result).to include("fa-arrows-left-right")
    end

    it "returns neutral badge for unknown match type" do
      tc = build(:test_case)
      allow(tc).to receive(:match_type).and_return("unknown")
      result = helper.test_case_match_type_badge(tc)
      expect(result).to include("badge-neutral")
      expect(result).to include("fa-circle")
    end
  end

  describe "#test_case_expected_status_badge_for" do
    it "returns success badge for completed status" do
      result = helper.test_case_expected_status_badge_for("completed")
      expect(result).to include("badge-success")
      expect(result).to include("Completed")
    end

    it "returns danger badge for failed status" do
      result = helper.test_case_expected_status_badge_for("failed")
      expect(result).to include("badge-danger")
      expect(result).to include("Failed")
    end
  end

  describe "#test_case_expected_status_badge" do
    it "delegates to test_case_expected_status_badge_for" do
      tc = build(:test_case, :mission_case, expected_status: "completed")
      result = helper.test_case_expected_status_badge(tc)
      expect(result).to include("badge-success")
      expect(result).to include("Completed")
    end
  end

  describe "#test_run_status_badge" do
    ["pending", "running", "evaluating", "completed", "failed", "cancelled"].each do |status|
      it "returns a badge for #{status} status" do
        run = build(:test_suite_run, status:)
        result = helper.test_run_status_badge(run)
        expect(result).to include("badge")
        expect(result).to include(status.capitalize)
      end
    end
  end

  describe "#test_result_status_badge" do
    ["pending", "running", "evaluating", "passed", "failed", "error"].each do |status|
      it "returns a badge for #{status} status" do
        result_record = build(:test_case_result, status:)
        result = helper.test_result_status_badge(result_record)
        expect(result).to include("badge")
        expect(result).to include(status.capitalize == "Error" ? "Error" : status.capitalize)
      end
    end
  end

  describe "#test_result_score_display" do
    it "returns dash for nil score" do
      result = build(:test_case_result, score: nil)
      expect(helper.test_result_score_display(result)).to eq("—")
    end

    it "returns green percentage for high score" do
      result = build(:test_case_result, score: 0.95)
      html = helper.test_result_score_display(result)
      expect(html).to include("95%")
      expect(html).to include("text-green-500")
    end

    it "returns amber percentage for medium score" do
      result = build(:test_case_result, score: 0.6)
      html = helper.test_result_score_display(result)
      expect(html).to include("60%")
      expect(html).to include("text-amber-500")
    end

    it "returns red percentage for low score" do
      result = build(:test_case_result, score: 0.3)
      html = helper.test_result_score_display(result)
      expect(html).to include("30%")
      expect(html).to include("text-red-500")
    end
  end

  describe "#test_run_pass_rate_display" do
    it "returns dash when total is zero" do
      run = build(:test_suite_run, total_count: 0)
      expect(helper.test_run_pass_rate_display(run)).to eq("—")
    end

    it "returns colored percentage" do
      run = build(:test_suite_run, total_count: 10, passed_count: 9)
      html = helper.test_run_pass_rate_display(run)
      expect(html).to include("90.0%")
      expect(html).to include("text-green-500")
    end
  end

  describe "#test_run_duration_display" do
    it "returns dash for nil duration" do
      run = build(:test_suite_run, duration_ms: nil)
      expect(helper.test_run_duration_display(run)).to eq("—")
    end

    it "returns seconds for short durations" do
      run = build(:test_suite_run, duration_ms: 5000)
      expect(helper.test_run_duration_display(run)).to eq("5.0s")
    end

    it "returns minutes and seconds for longer durations" do
      run = build(:test_suite_run, duration_ms: 90_000)
      expect(helper.test_run_duration_display(run)).to eq("1m 30s")
    end
  end

  describe "#test_result_duration_display" do
    it "returns dash for nil duration" do
      result = build(:test_case_result, duration_ms: nil)
      expect(helper.test_result_duration_display(result)).to eq("—")
    end

    it "returns seconds" do
      result = build(:test_case_result, duration_ms: 2500)
      expect(helper.test_result_duration_display(result)).to eq("2.5s")
    end
  end

  describe "#test_run_cost_display" do
    it "returns dash when cost is zero" do
      run = create(:test_suite_run)
      expect(helper.test_run_cost_display(run)).to eq("—")
    end
  end

  describe "#test_run_input_tokens_display" do
    it "returns dash when tokens are zero" do
      run = create(:test_suite_run)
      expect(helper.test_run_input_tokens_display(run)).to eq("—")
    end
  end

  describe "#test_run_output_tokens_display" do
    it "returns dash when tokens are zero" do
      run = create(:test_suite_run)
      expect(helper.test_run_output_tokens_display(run)).to eq("—")
    end
  end

  describe "#test_result_cost_display" do
    it "returns dash when cost is zero" do
      result = build(:test_case_result)
      expect(helper.test_result_cost_display(result)).to eq("—")
    end
  end

  describe "#test_result_input_tokens_display" do
    it "returns dash when tokens are zero" do
      result = build(:test_case_result)
      expect(helper.test_result_input_tokens_display(result)).to eq("—")
    end

    it "returns formatted count when tokens present" do
      result = create(:test_case_result, :with_chat)
      create(:message, chat: result.chat, input_tokens: 1500, output_tokens: 0)
      expect(helper.test_result_input_tokens_display(result)).to eq("1,500")
    end
  end

  describe "#test_result_output_tokens_display" do
    it "returns dash when tokens are zero" do
      result = build(:test_case_result)
      expect(helper.test_result_output_tokens_display(result)).to eq("—")
    end

    it "returns formatted count when tokens present" do
      result = create(:test_case_result, :with_chat)
      create(:message, chat: result.chat, input_tokens: 0, output_tokens: 2000)
      expect(helper.test_result_output_tokens_display(result)).to eq("2,000")
    end
  end

  describe "#test_result_agent_breakdown_display" do
    it "returns breakdown with dashes when no data" do
      result = build(:test_case_result)
      display = helper.test_result_agent_breakdown_display(result)
      expect(display).to include("In: —")
      expect(display).to include("Out: —")
      expect(display).to include("Cost: —")
    end
  end

  describe "#test_result_evaluator_breakdown_display" do
    it "returns breakdown with dashes when no data" do
      result = build(:test_case_result)
      display = helper.test_result_evaluator_breakdown_display(result)
      expect(display).to include("In: —")
      expect(display).to include("Out: —")
      expect(display).to include("Cost: —")
    end
  end

  describe "#test_run_agent_breakdown_display" do
    it "returns breakdown with dashes when no data" do
      run = create(:test_suite_run)
      display = helper.test_run_agent_breakdown_display(run)
      expect(display).to include("In: —")
    end
  end

  describe "#test_run_evaluator_breakdown_display" do
    it "returns breakdown with dashes when no data" do
      run = create(:test_suite_run)
      display = helper.test_run_evaluator_breakdown_display(run)
      expect(display).to include("In: —")
    end
  end

  describe "#test_run_tokens_display" do
    it "returns formatted token display" do
      run = create(:test_suite_run)
      display = helper.test_run_tokens_display(run)
      expect(display).to include("In:")
      expect(display).to include("Out:")
    end
  end

  describe "#test_result_tokens_display" do
    it "returns formatted token display" do
      result = build(:test_case_result)
      display = helper.test_result_tokens_display(result)
      expect(display).to include("In:")
      expect(display).to include("Out:")
    end
  end

  describe "#test_case_behavior_summary" do
    it "returns none when no behavior expectations exist" do
      test_case = build(:test_case)

      expect(helper.test_case_behavior_summary(test_case)).to include("None")
    end

    it "renders configured behavior expectations" do
      test_case = build(
        :test_case,
        expected_child_builtin_key: "agent_designer",
        expected_tool_names: ["ask_agent_agent_designer"],
        disallow_child_chats: true,
        required_keywords: ["Done"],
        forbidden_keywords: ["cannot"],
      )

      html = helper.test_case_behavior_summary(test_case)

      expect(html).to include("Child: agent_designer")
      expect(html).to include("No child chats")
      expect(html).to include("Tools: ask_agent_agent_designer")
      expect(html).to include("Keywords: Done")
      expect(html).to include("Forbidden: cannot")
    end

    it "omits unset behavior expectation fragments" do
      test_case = build(:test_case, expected_tool_names: ["list_resources"])

      html = helper.test_case_behavior_summary(test_case)

      expect(html).to include("Tools: list_resources")
      expect(html).not_to include("Child:")
      expect(html).not_to include("No child chats")
      expect(html).not_to include("Keywords:")
      expect(html).not_to include("Forbidden:")
    end

    it "renders child-only behavior expectations" do
      test_case = build(:test_case, expected_child_builtin_key: "agent_designer")

      html = helper.test_case_behavior_summary(test_case)

      expect(html).to include("Child: agent_designer")
      expect(html).not_to include("Tools:")
    end
  end

  describe "#test_case_list_value" do
    it "joins list values with newlines" do
      expect(helper.test_case_list_value(["one", "two"])).to eq("one\ntwo")
    end
  end

  describe "#test_result_check_display" do
    it "formats nil, true, and false states" do
      expect(helper.test_result_check_display(nil)).to eq("-")
      expect(helper.test_result_check_display(true)).to eq("passed")
      expect(helper.test_result_check_display(false)).to eq("failed")
    end
  end

  # ------------------------------------------------------------------
  # Additional branch-coverage specs
  # ------------------------------------------------------------------

  describe "non-zero cost/token paths" do
    let(:run) { create(:test_suite_run) }

    it "test_run_cost_display returns formatted cost when non-zero" do
      create(:test_case_result, :with_chat, test_suite_run: run)
      allow(run).to receive(:calculate_cost).and_return(0.00025)
      display = helper.test_run_cost_display(run)
      expect(display).to start_with("$")
    end

    it "test_run_input_tokens_display returns formatted when non-zero" do
      result_in_run = create(:test_case_result, :with_chat, test_suite_run: run)
      create(:message, chat: result_in_run.chat, input_tokens: 1200, output_tokens: 0)
      expect(helper.test_run_input_tokens_display(run)).to eq("1,200")
    end

    it "test_run_output_tokens_display returns formatted when non-zero" do
      result_in_run = create(:test_case_result, :with_chat, test_suite_run: run)
      create(:message, chat: result_in_run.chat, input_tokens: 0, output_tokens: 800)
      expect(helper.test_run_output_tokens_display(run)).to eq("800")
    end

    it "test_result_cost_display returns formatted cost when non-zero" do
      result_record = create(:test_case_result, :with_chat)
      allow(result_record).to receive(:calculate_cost).and_return(0.001)
      display = helper.test_result_cost_display(result_record)
      expect(display).to start_with("$")
    end
  end

  describe "non-zero breakdown paths" do
    let(:result_record) { create(:test_case_result, :with_chat) }

    before do
      # Set the chat's execution_context to :test for agent classification
      result_record.chat.update!(execution_context: :test)
      # Create an evaluator chat (execution_context :system, linked via parent_chat_id)
      evaluator_chat = create(:chat, parent_chat: result_record.chat, execution_context: :system)
      # Agent chat messages
      create(:message, chat: result_record.chat, input_tokens: 200, output_tokens: 100)
      # Evaluator chat messages
      create(:message, chat: evaluator_chat, input_tokens: 150, output_tokens: 80)
    end

    it "test_result_agent_breakdown_display shows non-zero values" do
      display = helper.test_result_agent_breakdown_display(result_record)
      expect(display).to include("200")
      expect(display).to include("100")
    end

    it "test_result_evaluator_breakdown_display shows non-zero values" do
      display = helper.test_result_evaluator_breakdown_display(result_record)
      expect(display).to include("150")
      expect(display).to include("80")
    end

    it "test_run_agent_breakdown_display shows non-zero values" do
      run = result_record.test_suite_run
      display = helper.test_run_agent_breakdown_display(run)
      expect(display).to include("200")
    end

    it "test_run_evaluator_breakdown_display shows non-zero values" do
      run = result_record.test_suite_run
      display = helper.test_run_evaluator_breakdown_display(run)
      expect(display).to include("150")
    end
  end

  describe "private #test_run_progress_color" do
    it "returns neutral for pending run" do
      run = build(:test_suite_run, :pending)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-neutral-300")
    end

    it "returns brand for running run" do
      run = build(:test_suite_run, :running)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-brand-500")
    end

    it "returns brand for evaluating run" do
      run = build(:test_suite_run, :evaluating)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-brand-500")
    end

    it "returns danger for failed run" do
      run = build(:test_suite_run, :failed)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-danger-500")
    end

    it "returns success for high pass rate completed run" do
      run = build(:test_suite_run, :completed, total_count: 10, passed_count: 9)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-success-500")
    end

    it "returns warning for medium pass rate" do
      run = build(:test_suite_run, :completed, total_count: 10, passed_count: 6, failed_count: 4)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-warning-500")
    end

    it "returns danger for low pass rate" do
      run = build(:test_suite_run, :completed, total_count: 10, passed_count: 2, failed_count: 8)
      expect(helper.send(:test_run_progress_color, run)).to eq("bg-danger-500")
    end
  end

  describe "private #score_color" do
    it "returns green for high scores" do
      expect(helper.send(:score_color, 0.9)).to eq("text-green-500")
    end

    it "returns amber for medium scores" do
      expect(helper.send(:score_color, 0.6)).to eq("text-amber-500")
    end

    it "returns red for low scores" do
      expect(helper.send(:score_color, 0.3)).to eq("text-red-500")
    end
  end

  describe "pass rate color via test_run_pass_rate_display" do
    it "returns amber for medium pass rate" do
      run = build(:test_suite_run, total_count: 10, passed_count: 6)
      html = helper.test_run_pass_rate_display(run)
      expect(html).to include("text-amber-500")
    end

    it "returns red for low pass rate" do
      run = build(:test_suite_run, total_count: 10, passed_count: 3)
      html = helper.test_run_pass_rate_display(run)
      expect(html).to include("text-red-500")
    end
  end

  describe "else branch coverage for unknown status values" do
    let(:run_with_unknown_status) do
      r = build(:test_suite_run)
      allow(r).to receive_messages(status: "custom_status", pending?: false, in_progress?: false, failed?: false)
      r
    end

    let(:result_with_unknown_status) do
      r = build(:test_case_result)
      allow(r).to receive(:status).and_return("custom_result_status")
      r
    end

    it "returns capitalized status for run_status_label with unknown status" do
      expect(helper.send(:run_status_label, run_with_unknown_status)).to eq("Custom_status")
    end

    it "returns badge-neutral for run_status_css with unknown status" do
      expect(helper.send(:run_status_css, run_with_unknown_status)).to eq("badge-neutral")
    end

    it "returns circle icon for run_status_icon with unknown status" do
      expect(helper.send(:run_status_icon, run_with_unknown_status)).to eq("fa-solid fa-circle")
    end

    it "returns capitalized status for result_status_label with unknown status" do
      expect(helper.send(:result_status_label, result_with_unknown_status)).to eq("Custom_result_status")
    end

    it "returns badge-neutral for result_status_css with unknown status" do
      expect(helper.send(:result_status_css, result_with_unknown_status)).to eq("badge-neutral")
    end

    it "returns circle icon for result_status_icon with unknown status" do
      expect(helper.send(:result_status_icon, result_with_unknown_status)).to eq("fa-solid fa-circle")
    end
  end
end
