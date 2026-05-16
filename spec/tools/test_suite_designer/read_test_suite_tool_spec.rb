# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteDesigner::ReadTestSuiteTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:agent_record) { create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1") }
  let(:test_suite) do
    create(
      :test_suite,
      agent: agent_record,
      name: "Regression Smoke",
      description: "Checks the main support flow",
      evaluation_model_id: "gpt-4.1-mini",
    )
  end
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation:,
    )
  end

  before do
    create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours", match_type: "exact")
    create(
      :test_suite_run,
      test_suite:,
      status: :completed,
      total_count: 1,
      passed_count: 1,
      completed_at: Time.current,
    )
  end

  describe "#name" do
    it "returns read_test_suite" do
      expect(described_class.new(runtime_context:).name).to eq("read_test_suite")
    end
  end

  describe "#execute" do
    it "reads the current test suite details, test cases, and latest run guidance" do
      result = described_class.new(runtime_context:, current_test_suite: test_suite).execute

      expect(result).to include(
        "## Test Suite",
        "Regression Smoke",
        "Support Agent",
        "## Test Cases",
        "What is our SLA?",
        "## Latest Run",
        "read_test_suite_run",
        "## Editable Attribute Keys",
        "manage_record(resource: \"test_suite\", ...)",
        "manage_test_case",
      )
    end

    it "uses the nested test_suite_id page param when the current suite is not passed explicitly" do
      contextual_runtime_context = runtime_context.with(
        ui_context: {
          "page" => { "params" => { "test_suite_id" => test_suite.id.to_s } },
        },
      )

      result = described_class.new(runtime_context: contextual_runtime_context).execute

      expect(result).to include("Regression Smoke")
    end

    it "finds a test suite by unique name inside the current scope" do
      result = described_class.new(runtime_context:).execute(test_suite_id: test_suite.name)

      expect(result).to include("Regression Smoke")
    end

    it "includes agent behavior assertions in test case summaries" do
      create(
        :test_case,
        test_suite:,
        prompt: "Check behavior",
        expected_answer: "Done",
        expected_child_builtin_key: "agent_designer",
        expected_tool_names: ["ask_agent_agent_designer"],
        disallow_child_chats: true,
        required_keywords: ["Done"],
        forbidden_keywords: ["cannot"],
      )
      expected_behavior = "behavior=child=agent_designer;no_child_chats;tools=ask_agent_agent_designer;" \
                          "required=Done;forbidden=cannot"

      result = described_class.new(runtime_context:, current_test_suite: test_suite).execute

      expect(result).to include(expected_behavior)
    end

    it "omits unset agent behavior fragments in test case summaries" do
      create(
        :test_case,
        test_suite:,
        prompt: "Check behavior",
        expected_answer: "Done",
        expected_tool_names: ["list_resources"],
      )

      result = described_class.new(runtime_context:, current_test_suite: test_suite).execute

      expect(result).to include("behavior=tools=list_resources")
      expect(result).not_to include("no_child_chats")
      expect(result).not_to include("required=")
    end

    it "summarizes behavior expectations without tools" do
      create(
        :test_case,
        test_suite:,
        prompt: "Check delegation",
        expected_answer: "Done",
        expected_child_builtin_key: "agent_designer",
      )

      result = described_class.new(runtime_context:, current_test_suite: test_suite).execute

      expect(result).to include("behavior=child=agent_designer")
      expect(result).not_to include("tools=")
    end

    it "includes mission input variable keys in test case summaries" do
      mission = create(:mission, operation:)
      mission_suite = create(:test_suite, :mission_suite, mission:)
      create(
        :test_case,
        :mission_case,
        test_suite: mission_suite,
        input_variables: { "ticket_id" => "123" },
      )

      result = described_class.new(runtime_context:, current_test_suite: mission_suite).execute

      expect(result).to include("input_keys=ticket_id")
    end

    it "returns a helpful message when there is no current suite" do
      expect(described_class.new(runtime_context:).execute).to eq(
        "No current test suite is available. Pass test_suite_id after creating one or open a test suite page first.",
      )
    end
  end
end
