# frozen_string_literal: true

# rubocop:disable Style/FormatStringToken

require "rails_helper"

RSpec.describe BuiltinTestSuites::Synchronizer do
  let(:tenant) { create(:tenant) }

  describe ".ensure_present!" do
    it "creates builtin Agent Alpha suites in Headquarter" do
      result = described_class.ensure_present!(tenant:)

      suites = Agent.find_builtin_by_key("agent_alpha", tenant:).test_suites.builtin

      expect(result.created_keys).to include("agent-alpha-knowledge")
      expect(suites.count).to eq(9)
      expect(suites.sum { |suite| suite.test_cases.count }).to eq(100)
    end

    it "persists behavior fields on builtin test cases" do
      described_class.ensure_present!(keys: ["agent-alpha-mission"], tenant:)

      suite = builtin_suite("agent-alpha-mission")
      test_case = suite.test_cases.find_by!(scenario_key: "mission-01")

      expect(test_case).to have_attributes(
        source_type: "builtin",
        category: "mission",
        complexity: "medium",
        fixture_key: "agent_alpha_benchmark",
        expected_child_builtin_key: "mission_designer",
        expected_tool_names: ["ask_agent_mission_designer"],
      )
      expect(test_case.required_keywords).to eq(["%{new_mission_name}"])
    end

    it "preserves edited builtin suite fields until restore" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      suite = builtin_suite("agent-alpha-knowledge")
      suite.update!(name: "Customized Knowledge Suite")

      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)

      expect(suite.reload.name).to eq("Customized Knowledge Suite")
    end

    it "returns an empty result when no definitions are selected" do
      allow(BuiltinTestSuites::DefinitionLoader).to receive(:load_all).and_return([])

      result = described_class.ensure_present!(tenant:)

      expect(result.created_keys).to eq([])
      expect(result.restored_keys).to eq([])
    end

    it "raises for unknown requested builtin suite keys" do
      expect { described_class.ensure_present!(keys: ["missing-suite"], tenant:) }
        .to raise_error(RuntimeError, /Unknown builtin test suite keys/)
    end

    it "skips target-agent synchronization when definitions do not target a builtin agent" do
      definition = BuiltinTestSuites::Definition.new(
        key: "manual-target-suite",
        name: "Manual Target Suite",
        description: "No target agent",
        suite_type: "agent",
        target_builtin_agent_key: nil,
        evaluation_temperature: 0.2,
        fixture_key: nil,
        test_cases: [],
        source_path: Rails.root.join("config/builtin_tests/manual-target.toml"),
      )
      allow(BuiltinAgents::Synchronizer).to receive(:ensure_present!)

      service = described_class.new(tenant:)
      service.send(:ensure_target_agents!, [definition])

      expect(BuiltinAgents::Synchronizer).not_to have_received(:ensure_present!)
      expect(service.send(:target_agent_for, definition)).to be_nil
    end

    it "removes stale builtin suites during full sync" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      stale_suite = TestSuite.builtin.create!(
        name: "Stale Builtin Suite",
        suite_type: "agent",
        agent: Agent.find_builtin_by_key("agent_alpha", tenant:),
        source_metadata: { "builtin_key" => "stale-suite" },
      )

      described_class.ensure_present!(keys: nil, tenant:)

      expect(TestSuite.exists?(stale_suite.id)).to be(false)
    end

    it "removes stale builtin test cases from existing suites" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      suite = builtin_suite("agent-alpha-knowledge")
      stale_case = suite.test_cases.create!(
        source_type: "builtin",
        source_metadata: { "builtin_key" => "stale-case" },
        scenario_key: "stale-case",
        prompt: "stale",
        expected_answer: "stale",
      )

      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)

      expect(TestCase.exists?(stale_case.id)).to be(false)
    end

    it "keeps existing evaluation connectors while syncing locked attributes" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      suite = builtin_suite("agent-alpha-knowledge")
      connector = create(:connector, :llm_provider, tenant:)
      suite.update!(evaluation_llm_connector: connector)

      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)

      expect(suite.reload.evaluation_llm_connector).to eq(connector)
    end
  end

  describe ".restore!" do
    it "restores editable fields from TOML" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      suite = builtin_suite("agent-alpha-knowledge")
      suite.update!(name: "Customized Knowledge Suite")

      described_class.restore!("agent-alpha-knowledge", tenant:)

      expect(suite.reload.name).to eq("Agent Alpha Knowledge Scenarios")
    end
  end

  describe ".restore_all!" do
    it "restores all builtin test suites" do
      described_class.ensure_present!(keys: ["agent-alpha-knowledge"], tenant:)
      suite = builtin_suite("agent-alpha-knowledge")
      suite.update!(name: "Customized Knowledge Suite")

      result = described_class.restore_all!(tenant:)

      expect(result.restored_keys).to include("agent-alpha-knowledge")
      expect(suite.reload.name).to eq("Agent Alpha Knowledge Scenarios")
    end
  end

  describe "private cleanup helpers" do
    it "clears inherited ordering before batching stale builtin test cases" do
      synchronizer = described_class.new(tenant:)
      suite = create(:test_suite, agent: create(:agent, operation: tenant.ensure_core_resources!.default_operation))
      create_builtin_test_case(suite, "kept-case")
      stale_test_case = create_builtin_test_case(suite, "stale-case")
      definition = instance_double(BuiltinTestSuites::TestCaseDefinition, key: "kept-case")
      suite_definition = instance_double(BuiltinTestSuites::Definition, test_cases: [definition])

      test_cases_relation = suite.test_cases
      builtin_relation = test_cases_relation.builtin

      allow(suite).to receive(:test_cases).and_return(test_cases_relation)
      allow(test_cases_relation).to receive(:builtin).and_return(builtin_relation)
      allow(builtin_relation).to receive(:reorder).and_call_original

      synchronizer.send(:destroy_stale_test_cases!, suite, suite_definition)

      expect(builtin_relation).to have_received(:reorder).with(nil)
      expect(TestCase.exists?(stale_test_case.id)).to be(false)
    end
  end

  def builtin_suite(key)
    TestSuite.builtin.where("source_metadata ->> 'builtin_key' = ?", key).first!
  end

  def create_builtin_test_case(test_suite, key)
    create(
      :test_case,
      test_suite:,
      source_type: "builtin",
      source_metadata: { "builtin_key" => key },
      scenario_key: key,
    )
  end
end
# rubocop:enable Style/FormatStringToken
