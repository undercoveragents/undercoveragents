# frozen_string_literal: true

# == Schema Information
#
# Table name: test_suites
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  description                 :text
#  evaluation_temperature      :float            default(0.7), not null
#  name                        :string           not null
#  slug                        :string
#  source_metadata             :jsonb            not null
#  source_type                 :string           default("manual"), not null
#  status                      :string           default("active"), not null
#  suite_type                  :string           default("agent"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  agent_id                    :bigint
#  evaluation_llm_connector_id :bigint
#  evaluation_model_id         :string
#  mission_id                  :bigint
#
# Indexes
#
#  index_test_suites_on_agent_id                     (agent_id)
#  index_test_suites_on_builtin_key                  (((source_metadata ->> 'builtin_key'::text))) WHERE ((source_type)::text = 'builtin'::text)
#  index_test_suites_on_evaluation_llm_connector_id  (evaluation_llm_connector_id)
#  index_test_suites_on_mission_id                   (mission_id)
#  index_test_suites_on_name                         (name)
#  index_test_suites_on_slug                         (slug) UNIQUE
#  index_test_suites_on_source_type                  (source_type)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (evaluation_llm_connector_id => connectors.id)
#  fk_rails_...  (mission_id => missions.id)
#
require "rails_helper"

RSpec.describe TestSuite do
  subject(:test_suite) { build(:test_suite) }

  describe "associations" do
    it { is_expected.to belong_to(:agent).optional }
    it { is_expected.to belong_to(:mission).optional }
    it { is_expected.to belong_to(:evaluation_llm_connector).class_name("Connector").optional }
    it { is_expected.to have_many(:test_cases).dependent(:destroy).inverse_of(:test_suite) }
    it { is_expected.to have_many(:test_suite_runs).dependent(:destroy).inverse_of(:test_suite) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(1000) }
    it { is_expected.to validate_length_of(:evaluation_model_id).is_at_most(200) }
    it { is_expected.to validate_inclusion_of(:source_type).in_array(["manual", "builtin"]) }

    it {
      expect(test_suite).to validate_numericality_of(:evaluation_temperature)
        .is_greater_than_or_equal_to(0.0)
        .is_less_than_or_equal_to(2.0)
    }

    it "allows duplicate names" do
      existing = create(:test_suite)
      duplicate = build(:test_suite, name: existing.name, agent: create(:agent))

      expect(duplicate).to be_valid
    end

    context "when suite_type is agent" do
      it "requires agent_id" do
        suite = build(:test_suite, suite_type: "agent", agent: nil)
        expect(suite).not_to be_valid
        expect(suite.errors[:agent_id]).to include("can't be blank")
      end
    end

    context "when suite_type is mission" do
      it "requires mission_id" do
        suite = build(:test_suite, suite_type: "mission", agent: nil, mission: nil)
        expect(suite).not_to be_valid
        expect(suite.errors[:mission_id]).to include("can't be blank")
      end

      it "does not require agent_id" do
        suite = create(:test_suite, :mission_suite)
        expect(suite).to be_valid
      end
    end

    context "when evaluation_llm_connector is not an LLM provider" do
      it "is invalid" do
        sql_connector = create(:connector, :sql_database)
        suite = build(:test_suite, evaluation_llm_connector: sql_connector)
        expect(suite).not_to be_valid
        expect(suite.errors[:evaluation_llm_connector_id]).to include("must be an LLM Provider connector")
      end
    end

    context "when evaluation_llm_connector is a valid LLM provider" do
      it "is valid" do
        agent = create(:agent)
        llm_connector = create(:connector, :llm_provider, :enabled)
        suite = build(:test_suite, agent:, evaluation_llm_connector: llm_connector)
        expect(suite).to be_valid
      end
    end

    context "when evaluation_llm_connector_id is set but connector is deleted (orphan)" do
      it "adds an error (nil connector treated as non-LLM-provider)" do
        suite = build(:test_suite, evaluation_llm_connector_id: 999_999_999)
        expect(suite).not_to be_valid
        expect(suite.errors[:evaluation_llm_connector_id]).to include("must be an LLM Provider connector")
      end
    end
  end

  describe "enums" do
    it {
      expect(test_suite).to define_enum_for(:status)
        .with_values(active: "active", archived: "archived")
        .backed_by_column_of_type(:string)
    }

    it {
      expect(test_suite).to define_enum_for(:suite_type)
        .with_values(agent: "agent", mission: "mission")
        .backed_by_column_of_type(:string)
    }
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns test suites ordered by name" do
        agent = create(:agent)
        suite_b = create(:test_suite, name: "Beta Suite", agent:)
        suite_a = create(:test_suite, name: "Alpha Suite", agent:)

        expect(described_class.ordered).to eq([suite_a, suite_b])
      end
    end
  end

  describe "#builtin_key" do
    it "reads the builtin key from source metadata" do
      suite = build(:test_suite, source_type: "builtin", source_metadata: { "builtin_key" => "alpha" })

      expect(suite).to be_builtin
      expect(suite.builtin_key).to eq("alpha")
    end

    it "adds a validation error when source metadata is not a hash" do
      suite = build(:test_suite)
      suite.source_metadata = []

      suite.send(:source_metadata_must_be_hash)

      expect(suite.errors[:source_metadata]).to include("must be a JSON object")
    end

    it "normalizes invalid source metadata before validation" do
      suite = build(:test_suite)
      suite.source_metadata = []

      suite.valid?

      expect(suite.source_metadata).to eq({})
    end
  end

  describe "#can_run?" do
    it "returns true when active with test cases" do
      suite = create(:test_suite, :with_test_cases)
      expect(suite.can_run?).to be true
    end

    it "returns false when archived" do
      suite = create(:test_suite, :archived, :with_test_cases)
      expect(suite.can_run?).to be false
    end

    it "returns false when no test cases" do
      suite = create(:test_suite)
      expect(suite.can_run?).to be false
    end

    it "uses the preloaded test case count when available" do
      suite = create(:test_suite)
      suite.test_case_count = 1

      expect(suite.can_run?).to be true
    end
  end

  describe "#test_case_count" do
    it "uses the preloaded count when available" do
      suite = create(:test_suite)
      suite.test_case_count = 3

      expect(suite.test_case_count).to eq(3)
    end

    it "falls back to the association size" do
      suite = create(:test_suite, :with_test_cases)

      expect(suite.test_case_count).to eq(suite.test_cases.size)
    end
  end

  describe "#latest_run" do
    it "returns the most recent run" do
      suite = create(:test_suite)
      create(:test_suite_run, test_suite: suite, created_at: 2.days.ago) # older run
      newer_run = create(:test_suite_run, test_suite: suite, created_at: 1.day.ago)

      expect(suite.latest_run).to eq(newer_run)
    end
  end

  describe "friendly_id" do
    it "generates a slug from name" do
      suite = create(:test_suite, name: "My Test Suite")
      expect(suite.slug).to eq("my-test-suite")
    end

    it "regenerates slug when name changes" do
      suite = create(:test_suite, name: "Original Name")
      suite.update!(name: "Updated Name")
      expect(suite.slug).to eq("updated-name")
    end

    it "enforces globally unique slugs" do
      agent1 = create(:agent)
      agent2 = create(:agent)

      suite1 = create(:test_suite, name: "Name Alpha", agent: agent1)
      suite2 = create(:test_suite, name: "Name Beta", agent: agent2)

      expect(suite1.slug).to eq("name-alpha")
      expect(suite2.slug).to eq("name-beta")
      expect(suite1.slug).not_to eq(suite2.slug)
    end
  end

  describe "#resolved_evaluation_model_id" do
    it "returns evaluation_model_id when set" do
      suite = build(:test_suite, evaluation_model_id: "gpt-4o")
      expect(suite.resolved_evaluation_model_id).to eq("gpt-4o")
    end

    it "falls back to agent's model_id when blank" do
      agent = build(:agent, model_id: "claude-sonnet-4-20250514")
      suite = build(:test_suite, agent:, evaluation_model_id: nil)
      expect(suite.resolved_evaluation_model_id).to eq("claude-sonnet-4-20250514")
    end

    it "returns nil when no agent and no model_id" do
      suite = build(:test_suite, :mission_suite, evaluation_model_id: nil)
      expect(suite.resolved_evaluation_model_id).to be_nil
    end
  end

  describe "#resolve_evaluation_context" do
    it "uses evaluation_llm_connector when set" do
      llm_connector = create(:connector, :llm_provider)
      suite = create(:test_suite, evaluation_llm_connector: llm_connector)
      context = suite.resolve_evaluation_context
      expect(context).to be_a(RubyLLM::Context)
    end

    it "falls back to agent's llm_connector when not set" do
      suite = create(:test_suite, evaluation_llm_connector: nil)
      expect(suite.evaluation_llm_connector).to be_nil
      expect { suite.resolve_evaluation_context }.not_to raise_error
    end

    it "returns nil when no connectors available" do
      suite = build(:test_suite, :mission_suite, evaluation_llm_connector: nil)
      expect(suite.resolve_evaluation_context).to be_nil
    end
  end

  describe "#target" do
    it "returns agent for agent suites" do
      suite = create(:test_suite)
      expect(suite.target).to eq(suite.agent)
    end

    it "returns mission for mission suites" do
      suite = create(:test_suite, :mission_suite)
      expect(suite.target).to eq(suite.mission)
    end
  end

  describe "#target_name" do
    it "returns agent name for agent suites" do
      suite = create(:test_suite)
      expect(suite.target_name).to eq(suite.agent.name)
    end

    it "returns mission name for mission suites" do
      suite = create(:test_suite, :mission_suite)
      expect(suite.target_name).to eq(suite.mission.name)
    end

    it "returns nil when target is nil" do
      suite = build(:test_suite, suite_type: "agent", agent: nil)
      expect(suite.target_name).to be_nil
    end
  end

  describe "#target_icon" do
    it "returns agent icon for agent suites" do
      suite = build(:test_suite, suite_type: "agent")
      expect(suite.target_icon).to eq("fa-solid fa-user-secret")
    end

    it "returns mission icon for mission suites" do
      suite = build(:test_suite, suite_type: "mission")
      expect(suite.target_icon).to eq("fa-solid fa-diagram-project")
    end
  end

  describe "#suite_icon" do
    it "returns agent suite icon" do
      suite = build(:test_suite, suite_type: "agent")
      expect(suite.suite_icon).to eq("fa-solid fa-vial-circle-check")
    end

    it "returns mission suite icon" do
      suite = build(:test_suite, suite_type: "mission")
      expect(suite.suite_icon).to eq("fa-solid fa-flask-vial")
    end
  end

  describe "#input_fields" do
    it "returns empty array for agent suites" do
      suite = build(:test_suite, suite_type: "agent")
      expect(suite.input_fields).to eq([])
    end

    it "returns empty array when mission has nil flow_data" do
      mission = create(:mission)
      suite = build(:test_suite, :mission_suite, mission:)
      allow(mission).to receive(:flow_data).and_return(nil)
      expect(suite.input_fields).to eq([])
    end

    it "returns empty array when mission has no nodes" do
      mission = create(:mission, flow_data: {})
      suite = create(:test_suite, :mission_suite, mission:)
      expect(suite.input_fields).to eq([])
    end

    it "returns empty array when no input node" do
      mission = create(:mission, flow_data: { "nodes" => [{ "type" => "agent" }] })
      suite = create(:test_suite, :mission_suite, mission:)
      expect(suite.input_fields).to eq([])
    end

    it "returns fields from input node" do
      fields = [{ "key" => "name", "label" => "Name", "type" => "string" }]
      mission = create(:mission, flow_data: {
                         "nodes" => [{ "type" => "input", "data" => { "fields" => fields } }],
                       },)
      suite = create(:test_suite, :mission_suite, mission:)
      expect(suite.input_fields).to eq(fields)
    end
  end
end
