# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ManageAgentActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:headquarter) { tenant.headquarter_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context_for(current_operation, path:, current_object: nil)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => path },
        "current_object" => current_object,
      }.compact,
      user:,
      tenant:,
      operation: current_operation,
    )
  end

  describe "#name" do
    it "returns manage_agent_action" do
      context = runtime_context_for(operation, path: Rails.application.routes.url_helpers.admin_agents_path)

      expect(described_class.new(runtime_context: context).name).to eq("manage_agent_action")
    end
  end

  describe "#execute" do
    it "restores the current builtin agent and refreshes the current page" do
      agent_record = build(:agent, operation: headquarter, name: "Builtin Agent", model_id: "gpt-4.1", builtin: true)
      agent_record.builtin_key = "builtin-agent"
      agent_record.save!
      runtime_context = runtime_context_for(
        headquarter,
        path: Rails.application.routes.url_helpers.admin_agent_path(agent_record),
        current_object: { "class_name" => "Agent", "id" => agent_record.id },
      )
      tool = described_class.new(runtime_context:, current_agent: agent_record)

      allow(BuiltinAgents::Synchronizer).to receive(:restore!).with("builtin-agent", tenant:)
      allow(Agent).to receive(:find_builtin_by_key).with("builtin-agent", tenant:).and_return(agent_record)

      result = tool.execute(action: "restore")

      expect(result).to include("Built-in agent restored to the shipped defaults.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "refresh", path: Rails.application.routes.url_helpers.admin_agent_path(agent_record)),
      )
    end

    it "restores all builtin agents in Headquarter" do
      runtime_context = runtime_context_for(headquarter, path: Rails.application.routes.url_helpers.admin_agents_path)
      tool = described_class.new(runtime_context:)

      allow(BuiltinAgents::Synchronizer).to receive(:restore_all!).with(tenant:).and_return(
        double(restored_keys: ["agent_alpha"], created_keys: ["agent_designer"]),
      )

      result = Current.set(operation: headquarter, tenant:) do
        tool.execute(action: "restore_defaults")
      end

      expect(result).to include("Restored 2 built-in agents.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "refresh", path: Rails.application.routes.url_helpers.admin_agents_path),
      )
    end
  end
end
