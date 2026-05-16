# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory do
  let(:agent)     { create(:agent) }
  let(:user)      { create(:user) }
  let(:chat)      { instance_double(Chat, user:) }
  let(:connector) { create(:connector, :llm_provider, :enabled) }

  # Build a plain configurator instance (no DB record needed).
  def build_config(attrs = {})
    defaults = { model_id: "text-embedding-3-small", embedding_dimensions: 1536, auto_bootstrap: false }
    described_class.new(**defaults, **attrs)
  end

  describe ".permitted_params" do
    it "permits model_id, embedding_dimensions, auto_bootstrap, llm_connector_id" do
      raw = ActionController::Parameters.new(
        model_id: "text-embedding-3-small",
        embedding_dimensions: "1536",
        auto_bootstrap: "1",
        llm_connector_id: "42",
        forbidden: "ignored",
      )

      permitted = described_class.permitted_params(raw)

      expect(permitted.to_h.keys).to contain_exactly("model_id", "embedding_dimensions", "auto_bootstrap",
                                                     "llm_connector_id",)
      expect(permitted[:forbidden]).to be_nil
    end
  end

  describe "#tools_for" do
    context "when parent_chat is nil" do
      it "returns an empty array" do
        expect(build_config.tools_for(agent:, parent_chat: nil)).to eq([])
      end
    end

    context "when parent_chat has no user" do
      it "returns an empty array" do
        chatless = instance_double(Chat, user: nil)
        expect(build_config.tools_for(agent:, parent_chat: chatless)).to eq([])
      end
    end

    context "with a user already bootstrapped" do
      before { Capabilities::Memory::Bootstrapper.new(agent, user:).bootstrap! }

      it "returns memory_replace and memory_insert tools" do
        tools = build_config.tools_for(agent:, parent_chat: chat)
        expect(tools.map(&:name)).to contain_exactly("memory_replace", "memory_insert")
      end

      it "does not include archival tools when no connector is configured" do
        tools = build_config.tools_for(agent:, parent_chat: chat)
        expect(tools.map(&:name)).not_to include("archival_memory_insert", "archival_memory_search")
      end

      it "includes archival tools when a connector is configured" do
        config = build_config(llm_connector_id: connector.id)
        tools = config.tools_for(agent:, parent_chat: chat)
        expect(tools.map(&:name)).to include("archival_memory_insert", "archival_memory_search")
      end
    end

    context "when auto_bootstrap is true and user has no blocks yet" do
      it "bootstraps the user on the first call" do
        expect do
          build_config(auto_bootstrap: true).tools_for(agent:, parent_chat: chat)
        end.to change { agent.user_memory_blocks(user).count }.from(0).to(2)
      end
    end

    context "when auto_bootstrap is false and user has no blocks yet" do
      it "does not bootstrap" do
        expect do
          build_config(auto_bootstrap: false).tools_for(agent:, parent_chat: chat)
        end.not_to(change { agent.user_memory_blocks(user).count })
      end
    end
  end

  describe "#system_prompt_addition_for" do
    context "when user is nil" do
      it "returns nil" do
        expect(build_config.system_prompt_addition_for(agent:, user: nil)).to be_nil
      end
    end

    context "when user has no bootstrapped blocks" do
      it "returns nil" do
        expect(build_config.system_prompt_addition_for(agent:, user:)).to be_nil
      end
    end

    context "when user has bootstrapped blocks" do
      before { Capabilities::Memory::Bootstrapper.new(agent, user:).bootstrap! }

      it "returns the memory blocks XML envelope" do
        result = build_config.system_prompt_addition_for(agent:, user:)
        expect(result).to include("<memory_blocks>")
      end
    end
  end

  describe "#summary" do
    it "includes model_id and 'auto-bootstrap' when auto_bootstrap is true" do
      result = build_config(auto_bootstrap: true).summary
      expect(result).to include("text-embedding-3-small")
      expect(result).to include("auto-bootstrap")
    end

    it "does not include 'auto-bootstrap' when auto_bootstrap is false" do
      result = build_config(auto_bootstrap: false).summary
      expect(result).not_to include("auto-bootstrap")
    end

    it "includes 'no connector' when no llm_connector_id is set" do
      result = build_config.summary
      expect(result).to include("no connector")
    end

    it "includes the connector name when a connector is configured" do
      result = build_config(llm_connector_id: connector.id).summary
      expect(result).to include(connector.name)
    end
  end

  describe "#form_locals" do
    it "returns available LLM connectors" do
      enabled_connector = create(:connector, :llm_provider, :enabled)
      result = build_config.form_locals
      expect(result[:available_llm_connectors]).to include(enabled_connector)
    end

    it "uses the global connector scope when Current.tenant is not set" do
      connector = create(:connector, :llm_provider, :enabled)
      Current.reset

      config = build_config(llm_connector_id: connector.id)

      expect(config.embedding_connector).to eq(connector)
      expect(config.form_locals[:available_llm_connectors]).to include(connector)
    ensure
      Current.reset
    end

    it "restricts connector lookups to the current tenant when one is set" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      create(:connector, :llm_provider, :enabled, tenant: create(:tenant))
      Current.tenant = tenant

      config = build_config(llm_connector_id: connector.id)

      expect(config.embedding_connector).to eq(connector)
      expect(config.form_locals[:available_llm_connectors]).to contain_exactly(connector)
    ensure
      Current.reset
    end

    it "uses the owning agent tenant when available" do
      tenant = create(:tenant)
      agent = create(
        :agent,
        operation: create(:operation, tenant:),
        llm_connector: create(:connector, :llm_provider, :enabled, tenant:),
      )
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      foreign_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant))

      config = build_config(llm_connector_id: connector.id)
      config._agent_record = agent

      expect(config.embedding_connector).to eq(connector)
      expect(config.form_locals[:available_llm_connectors]).to include(connector)
      expect(config.form_locals[:available_llm_connectors]).not_to include(foreign_connector)
    end
  end

  describe "validations" do
    it "is valid with an llm provider connector" do
      config = build_config(llm_connector_id: connector.id)

      expect(config).to be_valid
    end

    it "rejects non-llm connectors" do
      sql_connector = create(:connector, :sql_database)
      config = build_config(llm_connector_id: sql_connector.id)

      expect(config).not_to be_valid
      expect(config.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "rejects missing connectors" do
      config = build_config(llm_connector_id: 999_999)

      expect(config).not_to be_valid
      expect(config.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end
  end
end
