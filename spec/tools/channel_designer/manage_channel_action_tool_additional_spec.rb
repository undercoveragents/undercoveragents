# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelDesigner::ManageChannelActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }

  def runtime_context_for(channel)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: { "page" => { "path" => Rails.application.routes.url_helpers.admin_channel_path(channel) } },
      user:,
      tenant:,
      operation:,
    )
  end

  it "returns user-facing errors for invalid or failing channel actions" do
    client_channel = create(:channel, :client, tenant:, name: "Client Channel")
    telegram_channel = create(:channel, :telegram, tenant:, name: "Telegram Bot")
    unsupported_tool = described_class.new(
      runtime_context: runtime_context_for(client_channel),
      current_channel: client_channel,
    )
    failing_tool = described_class.new(
      runtime_context: runtime_context_for(telegram_channel),
      current_channel: telegram_channel,
    )

    expect(unsupported_tool.execute(action: "setup_webhook")).to include("does not support webhook setup")
    allow(Telegram::WebhookSetupService).to receive(:new).and_raise(StandardError, "boom")
    expect(failing_tool.execute(action: "setup_webhook")).to eq("Error managing channel action: boom")
  end
end
