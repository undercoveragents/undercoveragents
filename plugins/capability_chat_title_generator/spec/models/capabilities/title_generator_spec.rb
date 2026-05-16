# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::TitleGenerator do
  describe "plugin metadata" do
    it "registers chat_title_generator key" do
      expect(described_class.key).to eq("chat_title_generator")
      expect(described_class.label).to eq("Chat Title Generator")
    end
  end

  describe "defaults" do
    subject(:config) { described_class.new }

    it { expect(config.max_length).to eq(30) }
    it { expect(config.max_turns).to eq(3) }
    it { expect(config.llm_config_source).to eq("inherit") }
  end

  describe "validations" do
    it "requires model_id for custom llm" do
      config = described_class.new(llm_config_source: "custom", model_id: nil)
      expect(config).not_to be_valid
      expect(config.errors[:model_id]).to include("can't be blank")
    end

    it "accepts custom connectors from the agent tenant" do
      tenant = create(:tenant)
      agent = create(
        :agent,
        operation: create(:operation, tenant:),
        llm_connector: create(:connector, :llm_provider, :enabled, tenant:),
      )
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      config = described_class.new(
        llm_config_source: "custom",
        llm_connector_id: connector.id,
        model_id: "gpt-4o-mini",
        temperature: 0.7,
      )
      config._agent_record = agent

      expect(config).to be_valid
    end

    it "rejects custom connectors outside the agent tenant" do
      tenant = create(:tenant)
      agent = create(:agent, operation: create(:operation, tenant:))
      foreign_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
      config = described_class.new(
        llm_config_source: "custom",
        llm_connector_id: foreign_connector.id,
        model_id: "gpt-4o-mini",
        temperature: 0.7,
      )
      config._agent_record = agent

      expect(config).not_to be_valid
      expect(config.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end
  end

  describe "#resolve_connector" do
    context "when inheriting LLM config and agent is present" do
      it "delegates to agent.resolved_llm_connector" do
        connector = create(:connector, :llm_provider, :enabled)
        agent = instance_double(Agent, resolved_llm_connector: connector, resolved_model_id: "gpt-4", temperature: 0.7)
        config = described_class.new(llm_config_source: "inherit")

        expect(config.resolve_connector(agent)).to eq(connector)
      end
    end

    context "when inheriting LLM config and agent is nil" do
      it "returns nil" do
        config = described_class.new(llm_config_source: "inherit")
        expect(config.resolve_connector(nil)).to be_nil
      end
    end

    context "when using custom LLM config" do
      it "scopes connector resolution through the agent tenant" do
        tenant = create(:tenant)
        operation = create(:operation, tenant:)
        agent = create(:agent, operation:)
        connector = create(:connector, :llm_provider, :enabled, tenant:)
        foreign_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
        config = described_class.new(llm_config_source: "custom", llm_connector_id: connector.id)
        config._agent_record = agent

        expect(config.resolve_connector(agent)).to eq(connector)

        config.llm_connector_id = foreign_connector.id
        expect(config.resolve_connector(agent)).to be_nil
      end
    end
  end

  describe "#to_configuration" do
    it "keeps custom llm fields when using custom config" do
      config = described_class.new(
        llm_config_source: "custom",
        llm_connector_id: 12,
        model_id: "gpt-4o-mini",
        temperature: 0.9,
      )

      expect(config.to_configuration).to include(
        "llm_config_source" => "custom",
        "llm_connector_id" => 12,
        "model_id" => "gpt-4o-mini",
        "temperature" => 0.9,
      )
    end
  end

  describe "#resolve_model_id" do
    context "when inheriting LLM config and agent is present" do
      it "delegates to agent.resolved_model_id" do
        agent = instance_double(Agent, resolved_llm_connector: nil, resolved_model_id: "gpt-4o", temperature: 0.5)
        config = described_class.new(llm_config_source: "inherit")

        expect(config.resolve_model_id(agent)).to eq("gpt-4o")
      end
    end

    context "when inheriting LLM config and agent is nil" do
      it "returns nil" do
        config = described_class.new(llm_config_source: "inherit")
        expect(config.resolve_model_id(nil)).to be_nil
      end
    end
  end

  describe "#resolve_temperature" do
    context "when inheriting LLM config and agent is present" do
      it "delegates to agent.temperature" do
        agent = instance_double(Agent, resolved_llm_connector: nil, resolved_model_id: "gpt-4", temperature: 1.2)
        config = described_class.new(llm_config_source: "inherit")

        expect(config.resolve_temperature(agent)).to eq(1.2)
      end
    end

    context "when inheriting LLM config and agent is nil" do
      it "returns nil" do
        config = described_class.new(llm_config_source: "inherit")
        expect(config.resolve_temperature(nil)).to be_nil
      end
    end
  end
end
