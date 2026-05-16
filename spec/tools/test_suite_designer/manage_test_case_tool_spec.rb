# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuiteDesigner::ManageTestCaseTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:agent_record) { create(:agent, operation:, model_id: "gpt-4.1") }
  let(:test_suite) { create(:test_suite, agent: agent_record, name: "Regression Smoke") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context_for(path:, current_object:)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => path },
        "current_object" => current_object,
      },
      user:,
      tenant:,
      operation:,
    )
  end

  def build_suite_tool
    context = runtime_context_for(
      path: Rails.application.routes.url_helpers.admin_test_suite_path(test_suite),
      current_object: { "class_name" => "TestSuite", "id" => test_suite.id },
    )

    described_class.new(runtime_context: context, current_test_suite: test_suite)
  end

  def expect_suite_refresh
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        path: Rails.application.routes.url_helpers.admin_test_suite_path(test_suite),
      ),
    )
  end

  describe "#name" do
    it "returns manage_test_case" do
      expect(build_suite_tool.name).to eq("manage_test_case")
    end
  end

  describe "#execute" do
    it "creates a test case in the current suite and refreshes the page" do
      result = build_suite_tool.execute(
        action: "create",
        attributes: {
          prompt: "What is our SLA?",
          expected_answer: "24 hours",
          match_type: "exact",
        },
      )

      expect(result).to include("Test case created successfully.")
      expect(test_suite.test_cases.find_by(prompt: "What is our SLA?")).to be_present
      expect_suite_refresh
    end

    it "creates behavior assertions from string and array attributes" do
      result = build_suite_tool.execute(
        action: "create",
        attributes: {
          prompt: "Check behavior",
          expected_answer: "Done",
          expected_tool_names: "tool_one, tool_two",
          required_keywords: ["Done", "Created"],
          forbidden_keywords: "cannot",
        },
      )

      test_case = test_suite.test_cases.find_by!(prompt: "Check behavior")
      expect(result).to include("Test case created successfully.")
      expect(test_case.expected_tool_names).to eq(["tool_one", "tool_two"])
      expect(test_case.required_keywords).to eq(["Done", "Created"])
      expect(test_case.forbidden_keywords).to eq(["cannot"])
    end

    it "returns an error for invalid list behavior attributes" do
      result = build_suite_tool.execute(
        action: "create",
        attributes: {
          prompt: "Check behavior",
          expected_answer: "Done",
          expected_tool_names: 123,
        },
      )

      expect(result).to include("List attributes must be an array or newline/comma-separated string")
    end

    it "updates a test case using its id" do
      test_case = create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours")

      result = build_suite_tool.execute(
        action: "update",
        test_case_id: test_case.id,
        attributes: { expected_answer: "48 hours" },
      )

      expect(result).to include("Test case updated successfully.")
      expect(test_case.reload.expected_answer).to eq("48 hours")
    end

    it "deletes a test case when confirm_destroy is true" do
      test_case = create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours")

      expect do
        result = build_suite_tool.execute(action: "delete", test_case_id: test_case.id, confirm_destroy: true)

        expect(result).to include("Test case deleted successfully.")
      end.to change(TestCase, :count).by(-1)
    end

    it "returns an error for unknown actions" do
      expect(build_suite_tool.execute(action: "archive")).to eq(
        "Error: Unknown action 'archive'. Use create, update, or delete.",
      )
    end

    it "returns an error when delete is missing confirm_destroy" do
      test_case = create(:test_case, test_suite:, prompt: "What is our SLA?", expected_answer: "24 hours")

      expect(build_suite_tool.execute(action: "delete", test_case_id: test_case.id)).to eq(
        "Error: confirm_destroy must be true for delete actions.",
      )
    end
  end
end
