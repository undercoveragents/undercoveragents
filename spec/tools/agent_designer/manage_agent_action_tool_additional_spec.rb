# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ManageAgentActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:headquarter) { tenant.headquarter_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }

  def runtime_context_for(path:)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: { "page" => { "path" => path } },
      user:,
      tenant:,
      operation: headquarter,
    )
  end

  it "returns user-facing errors for invalid or failing agent restore actions" do
    custom_agent = create(:agent, operation: headquarter, name: "Custom Agent", model_id: "gpt-4.1")
    tool = described_class.new(
      runtime_context: runtime_context_for(
        path: Rails.application.routes.url_helpers.admin_agent_path(custom_agent),
      ),
      current_agent: custom_agent,
    )

    expect(tool.execute(action: "restore")).to include("Headquarter is read-only")
    allow(BuiltinAgents::Synchronizer).to receive(:restore_all!).and_raise(StandardError, "boom")
    result = Current.set(operation: headquarter, tenant:) do
      described_class.new(
        runtime_context: runtime_context_for(
          path: Rails.application.routes.url_helpers.admin_agents_path,
        ),
      ).execute(action: "restore_defaults")
    end

    expect(result).to eq("Error managing agent action: boom")
  end
end
