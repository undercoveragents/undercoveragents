# frozen_string_literal: true

# rubocop:disable Style/FormatStringToken

require "rails_helper"

RSpec.describe BuiltinTestSuites::DefinitionLoader do
  describe ".load_all" do
    it "loads the shipped Agent Alpha builtin test suites" do
      definitions = described_class.load_all

      expect(definitions.map(&:key)).to include(
        "agent-alpha-knowledge",
        "agent-alpha-mission",
        "agent-alpha-test-suite",
      )
      expect(definitions.sum { |definition| definition.test_cases.size }).to eq(100)
    end

    it "loads behavior metadata from TOML" do
      definition = described_class.load_all.find { |item| item.key == "agent-alpha-mission" }
      test_case = definition.test_cases.find { |item| item.key == "mission-01" }

      expect(test_case).to have_attributes(
        category: "mission",
        complexity: "medium",
        expected_child_builtin_key: "mission_designer",
        expected_tool_names: ["ask_agent_mission_designer"],
        fixture_key: "agent_alpha_benchmark",
      )
      expect(test_case.required_keywords).to eq(["%{new_mission_name}"])
    end

    it "filters definitions by key" do
      definitions = described_class.load_for(["agent-alpha-mission"])

      expect(definitions.map(&:key)).to eq(["agent-alpha-mission"])
    end

    it "raises when duplicate suite keys are detected" do
      definition = described_class.load_for(["agent-alpha-mission"]).first

      expect { described_class.send(:detect_duplicate_keys!, [definition, definition]) }
        .to raise_error(RuntimeError, /Duplicate builtin test suite keys/)
    end

    it "raises when duplicate test case keys are detected" do
      definition = described_class.load_for(["agent-alpha-mission"]).first
      duplicate_definition = BuiltinTestSuites::Definition.new(
        key: "duplicate-suite",
        name: "Duplicate Suite",
        description: "Duplicate suite",
        suite_type: "agent",
        target_builtin_agent_key: "agent_alpha",
        evaluation_temperature: 0.2,
        fixture_key: nil,
        test_cases: [definition.test_cases.first, definition.test_cases.first],
        source_path: definition.source_path,
      )

      expect { described_class.send(:detect_duplicate_keys!, [duplicate_definition]) }
        .to raise_error(RuntimeError, /Duplicate builtin test case keys/)
    end

    it "handles disappearing files while building the cache signature" do
      signature = described_class.send(:definition_signature, ["/tmp/missing-builtin-test-suite.toml"])

      expect(signature).to eq([["/tmp/missing-builtin-test-suite.toml", nil, nil]])
    end
  end
end
# rubocop:enable Style/FormatStringToken
