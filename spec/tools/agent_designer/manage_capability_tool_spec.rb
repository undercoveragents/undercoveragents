# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ManageCapabilityTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def minimal_capability_class
    Class.new do
      include ActiveModel::Model

      attr_accessor :foo

      def self.label = "Minimal Capability"

      def self.permitted_params(raw)
        raw.permit(:foo)
      end

      def assign_attributes(attrs)
        self.foo = attrs["foo"]
      end

      def summary = ""

      def to_configuration = {}

      def after_capability_enabled(_agent)
        raise "callback boom"
      end
    end
  end

  def expect_agent_capability(agent, max_length:, max_turns:)
    capability = agent.reload.capability(:chat_title_generator)

    expect(agent.capability_enabled?(:chat_title_generator)).to be(true)
    expect(capability.max_length).to eq(max_length)
    expect(capability.max_turns).to eq(max_turns)
  end

  def expect_refresh_broadcast_for(agent)
    expect(ActionCable.server).to have_received(:broadcast).with(
      chat.ui_stream_channel_name,
      hash_including(
        type: "refresh",
        chat_id: chat.id,
        path: Rails.application.routes.url_helpers.admin_agent_path(agent),
      ),
    )
  end

  describe "#name" do
    it "returns manage_capability" do
      expect(described_class.new(runtime_context:).name).to eq("manage_capability")
    end
  end

  describe "#execute" do
    it "enables a capability on the current agent", :aggregate_failures do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context: runtime_context_for(agent), current_agent: agent)

      result = tool.execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: { max_length: 42, max_turns: 2 },
      )

      expect(result).to include("Capability configured successfully.", "`chat_title_generator`", "max 42 chars")
      expect(result).to include("Current page refresh started")
      expect_agent_capability(agent, max_length: 42, max_turns: 2)
      expect_refresh_broadcast_for(agent)
    end

    it "merges updates into an existing capability config" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 30,
                                    "max_turns" => 3,
                                    "llm_config_source" => "inherit",
                                  })
      agent.save!

      described_class.new(runtime_context:, current_agent: agent).execute(
        action: "update",
        capability_key: "chat_title_generator",
        config: { max_length: 55 },
      )

      capability = agent.reload.capability(:chat_title_generator)
      expect(capability.max_length).to eq(55)
      expect(capability.max_turns).to eq(3)
      expect(capability.llm_config_source).to eq("inherit")
    end

    it "accepts nil config and keeps plugin defaults" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
      )

      expect(result).to include("max 30 chars", "3 turns")
      expect(agent.reload.capability(:chat_title_generator).llm_config_source).to eq("inherit")
    end

    it "accepts ActionController parameters and JSON object strings as config" do
      params_agent = create(:agent, operation:, name: "Params Agent", model_id: "gpt-4.1")
      string_agent = create(:agent, operation:, name: "String Agent", model_id: "gpt-4.1")

      params_result = described_class.new(runtime_context:, current_agent: params_agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: ActionController::Parameters.new(max_length: 44, max_turns: 4),
      )
      string_result = described_class.new(runtime_context:, current_agent: string_agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: '{"max_length":45,"max_turns":5}',
      )

      expect(params_result).to include("max 44 chars")
      expect(string_result).to include("max 45 chars")
      expect(params_agent.reload.capability(:chat_title_generator).max_turns).to eq(4)
      expect(string_agent.reload.capability(:chat_title_generator).max_turns).to eq(5)
    end

    it "handles capabilities without an agent writer, summary, or persisted config payload" do
      agent = create(:agent, operation:, name: "Minimal Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:, current_agent: agent)
      allow(CapabilityPlugin).to receive(:resolve).with("minimal_capability").and_return(minimal_capability_class)
      allow(Rails.logger).to receive(:error)

      result = tool.execute(
        action: "set",
        capability_key: "minimal_capability",
        config: '{"foo":"bar"}',
      )

      expect(result).to include("Capability configured successfully.", "Minimal Capability")
      expect(result).not_to include("Summary:", "- Config:")
      expect(Rails.logger).to have_received(:error).with(/callback boom/)
      expect(agent.reload.capability_enabled?(:minimal_capability)).to be(true)
    end

    it "removes an assigned capability" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      agent.set_capability_config("chat_title_generator", { "max_length" => 30 })
      agent.save!

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "remove",
        capability_key: "chat_title_generator",
      )

      expect(result).to include("Capability removed successfully.")
      expect(agent.reload.capability_enabled?(:chat_title_generator)).to be(false)
    end

    it "reports when removing a capability that is not assigned" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "remove",
        capability_key: "chat_title_generator",
      )

      expect(result).to eq("Capability `chat_title_generator` is not currently assigned to Capability Agent.")
    end

    it "ignores malformed stored capability payloads when updating" do
      agent = create(:agent, operation:, name: "Malformed Agent", model_id: "gpt-4.1")
      agent.configuration = agent.configuration.merge(
        "capabilities" => { "chat_title_generator" => "not_a_hash" },
      )
      agent.save!(validate: false)

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: { max_length: 48 },
      )

      expect(result).to include("max 48 chars")
      expect(agent.reload.capability(:chat_title_generator).max_length).to eq(48)
    end

    it "treats non-hash agent configuration as missing capability storage" do
      agent = create(:agent, operation:, name: "Broken Config Agent", model_id: "gpt-4.1")
      agent.update_columns(configuration: "broken") # rubocop:disable Rails/SkipsModelValidations

      result = described_class.new(runtime_context:, current_agent: agent.reload).execute(
        action: "remove",
        capability_key: "chat_title_generator",
      )

      expect(result).to eq("Capability `chat_title_generator` is not currently assigned to Broken Config Agent.")
    end

    it "finds another agent inside the current operation by id" do
      agent = create(:agent, operation:, name: "Other Agent", model_id: "gpt-4.1")
      foreign_agent = create(:agent, operation: create(:operation, tenant:), name: "Foreign Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:)

      expect(tool.execute(
               action: "set",
               capability_key: "chat_title_generator",
               agent_id: agent.id,
               config: { max_length: 40 },
             )).to include("Other Agent")
      expect(
        tool.execute(
          action: "set",
          capability_key: "chat_title_generator",
          agent_id: foreign_agent.id,
          config: { max_length: 40 },
        ),
      ).to eq("Error: Agent '#{foreign_agent.id}' was not found.")
    end

    it "refuses to mutate agents in Headquarter" do
      headquarter_agent = create(
        :agent,
        operation: tenant.headquarter_operation,
        name: "Headquarter Agent",
        model_id: "gpt-4.1",
      )
      tool = described_class.new(
        runtime_context: runtime_context_for(headquarter_agent),
        current_agent: headquarter_agent,
      )

      result = tool.execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: { max_length: 40 },
      )

      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      expect(headquarter_agent.reload.capability_enabled?(:chat_title_generator)).to be(false)
    end

    it "returns helpful errors for unknown capability keys and invalid fields" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:, current_agent: agent)

      expect(tool.execute(action: "set", capability_key: "unknown_capability"))
        .to eq("Error: Unknown capability 'unknown_capability'. Use list_resources(kind: 'capabilities').")
      expect(tool.execute(action: "set", capability_key: "chat_title_generator", config: { unknown_field: 1 }))
        .to eq("Error: Unknown capability config keys: unknown_field")
    end

    it "rejects unsupported config payload types and malformed JSON payloads" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:, current_agent: agent)

      expect(tool.execute(action: "set", capability_key: "chat_title_generator", config: 123))
        .to eq("Error: Expected config to be a hash or JSON object string.")
      expect(tool.execute(action: "set", capability_key: "chat_title_generator", config: "[]"))
        .to eq("Error: Expected config to be a JSON object.")
      expect(tool.execute(action: "set", capability_key: "chat_title_generator", config: "{"))
        .to start_with("Error: ")
    end

    it "accepts blank JSON strings as empty config updates" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: "   ",
      )

      expect(result).to include("max 30 chars")
    end

    it "returns validation errors from the capability configurator" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
        config: { max_length: 0 },
      )

      expect(result).to eq("Error: Max length must be greater than 0")
    end

    it "returns record validation errors raised during save" do
      agent = build(:agent, operation:, name: nil, model_id: "gpt-4.1")

      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "set",
        capability_key: "chat_title_generator",
      )

      expect(result).to eq("Error: Name can't be blank")
    end

    it "rescues unexpected runtime errors" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:, current_agent: agent)
      allow(CapabilityPlugin).to receive(:resolve).with("chat_title_generator").and_raise(StandardError, "boom")

      result = tool.execute(action: "set", capability_key: "chat_title_generator")

      expect(result).to eq("Error managing capability: boom")
    end

    it "returns a helpful message when there is no current agent" do
      result = described_class.new(runtime_context:).execute(action: "set", capability_key: "chat_title_generator")

      expect(result).to eq(
        "No current agent is available. Pass agent_id after creating one or open an agent page first.",
      )
    end

    it "returns an error for unknown actions" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      result = described_class.new(runtime_context:, current_agent: agent).execute(
        action: "archive",
        capability_key: "chat_title_generator",
      )

      expect(result).to eq("Error: Unknown action 'archive'. Use set or remove.")
    end
  end

  def runtime_context_for(agent)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => Rails.application.routes.url_helpers.admin_agent_path(agent) },
        "current_object" => {
          "class_name" => "Agent",
          "id" => agent.id,
        },
      },
      user:,
      tenant:,
      operation:,
    )
  end
end
