# frozen_string_literal: true

# rubocop:disable Style/FormatStringToken

require "rails_helper"

RSpec.describe TestSuites::BehaviorEvaluator do
  let(:test_case) do
    build(
      :test_case,
      expected_child_builtin_key: "mission_designer",
      expected_tool_names: ["ask_agent_mission_designer"],
      required_keywords: ["%{new_mission_name}"],
      forbidden_keywords: ["cannot"],
    )
  end
  let(:context) { { new_mission_name: "AAB New Mission" } }

  it "passes when child chat, tool calls, and keywords match" do
    result = described_class.call(
      test_case:,
      response: "AAB New Mission is ready.",
      tool_names: ["ask_agent_mission_designer"],
      child_builtin_keys: ["mission_designer"],
      context:,
    )

    expect(result.passed).to be(true)
    expect(result.details).to be_empty
    expect(result.to_h).to eq(passed: true, analysis: "Behavior checks passed.", details: [])
  end

  it "reports missing child chats, tools, required keywords, and forbidden keywords" do
    result = described_class.call(
      test_case:,
      response: "I cannot do that.",
      tool_names: [],
      child_builtin_keys: [],
      context:,
    )

    expect(result.passed).to be(false)
    expect(result.analysis).to include("Expected child builtin 'mission_designer'")
    expect(result.analysis).to include("Missing expected tool calls")
    expect(result.analysis).to include("Missing expected response keywords")
    expect(result.analysis).to include("Response included forbidden keywords")
  end

  it "fails when child chats are disallowed" do
    test_case.expected_child_builtin_key = nil
    test_case.disallow_child_chats = true

    result = described_class.call(
      test_case:,
      response: "Done.",
      tool_names: [],
      child_builtin_keys: ["agent_designer"],
      context:,
    )

    expect(result.passed).to be(false)
    expect(result.analysis).to include("Expected no child designer chat")
  end
end
# rubocop:enable Style/FormatStringToken
