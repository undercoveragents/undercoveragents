# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinAgents::Runner do
  let(:agent) { instance_double(Agent, id: 42) }
  let(:chat) { instance_double(Chat, agent_id: nil, user: nil, agent: nil, mission: nil) }
  let(:tenant) { create(:tenant) }

  before do
    allow(BuiltinAgents::Resolver).to receive(:find!).with("agent_alpha", tenant:).and_return(agent)
    allow(Tenant).to receive(:default_tenant).and_return(tenant)
  end

  describe ".build_chat!" do
    it "delegates chat construction to the resolved builtin agent" do
      allow(agent).to receive(:build_chat).and_return(chat)

      result = described_class.build_chat!(
        builtin_key: "agent_alpha",
        model_id: "gpt-4o",
        input_values: { task: "demo" },
        runtime_context: { mission: :demo },
      )

      expect(result).to eq(chat)
      expect(agent).to have_received(:build_chat).with(
        hash_including(
          model_id: "gpt-4o",
          input_values: { task: "demo" },
          runtime_context: { mission: :demo },
        ),
      )
    end
  end

  describe ".configure_chat!" do
    it "updates the chat agent when needed and configures the chat" do
      allow(chat).to receive(:update!)
      allow(chat).to receive(:configure_for_agent)

      described_class.configure_chat!(chat:, builtin_key: "agent_alpha", input_values: { task: "demo" })

      expect(chat).to have_received(:update!).with(agent:)
      expect(chat).to have_received(:configure_for_agent).with(
        agent,
        hash_including(input_values: { task: "demo" }),
      )
    end

    it "skips the agent update when the chat already points at the builtin agent" do
      allow(chat).to receive(:agent_id).and_return(42)
      allow(chat).to receive(:update!)
      allow(chat).to receive(:configure_for_agent)

      described_class.configure_chat!(chat:, builtin_key: "agent_alpha")

      expect(chat).not_to have_received(:update!)
      expect(chat).to have_received(:configure_for_agent)
    end
  end

  describe ".ask!" do
    it "builds the chat and forwards the prompt" do
      allow(described_class).to receive(:build_chat!).and_return(chat)
      allow(chat).to receive(:ask).with("Hello").and_return("Hi")

      expect(described_class.ask!(builtin_key: "agent_alpha", prompt: "Hello")).to eq("Hi")
      expect(described_class).to have_received(:build_chat!).with(hash_including(builtin_key: "agent_alpha"))
    end
  end

  describe ".resolve_tenant" do
    it "uses the tenant from a chat mission when no explicit tenant is provided" do
      mission_tenant = create(:tenant)
      mission_scoped_chat = instance_double(
        Chat,
        agent: nil,
        mission: instance_double(Mission, operation: instance_double(Operation, tenant: mission_tenant)),
      )

      expect(described_class.resolve_tenant(tenant: nil, chat: mission_scoped_chat)).to eq(mission_tenant)
    end

    it "uses a tenant from the runtime context when available" do
      runtime_tenant = create(:tenant)
      runtime_value = Struct.new(:tenant).new(runtime_tenant)

      expect(
        described_class.resolve_tenant(tenant: nil, runtime_context: { mission: runtime_value }),
      ).to eq(runtime_tenant)
    end

    it "uses the tenant from the user when chat and runtime context do not resolve one" do
      user_tenant = create(:tenant)
      user = build_stubbed(:user, tenant: user_tenant)

      expect(
        described_class.resolve_tenant(tenant: nil, user:, runtime_context: { mission: Object.new }),
      ).to eq(user_tenant)
    end

    it "uses an operation tenant from the runtime context when the value has no tenant" do
      operation_tenant = create(:tenant)
      runtime_value = Struct.new(:operation).new(instance_double(Operation, tenant: operation_tenant))

      expect(
        described_class.resolve_tenant(tenant: nil, runtime_context: { mission: runtime_value }),
      ).to eq(operation_tenant)
    end
  end
end
