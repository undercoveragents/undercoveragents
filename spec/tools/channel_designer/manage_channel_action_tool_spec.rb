# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelDesigner::ManageChannelActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  def runtime_context_for(channel)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context: {
        "page" => { "path" => Rails.application.routes.url_helpers.admin_channel_path(channel) },
        "current_object" => { "class_name" => "Channel", "id" => channel.id },
      },
      user:,
      tenant:,
      operation:,
    )
  end

  describe "#name" do
    it "returns manage_channel_action" do
      channel = create(:channel, :api, tenant:)

      expect(described_class.new(runtime_context: runtime_context_for(channel)).name).to eq("manage_channel_action")
    end
  end

  describe "#execute" do
    it "regenerates an API channel token and refreshes the page" do
      channel = create(:channel, :api, tenant:, name: "Public API")
      create(:channel_credential, channel:, name: "Primary token", credential_type: "bearer_token")
      tool = described_class.new(runtime_context: runtime_context_for(channel), current_channel: channel)

      result = tool.execute(action: "regenerate_token")

      expect(result).to include("Channel action completed.", "Action: `regenerate_token`", "New token: `")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "refresh", path: Rails.application.routes.url_helpers.admin_channel_path(channel)),
      )
    end

    it "runs supported webhook setup actions for Telegram channels" do
      channel = create(:channel, :telegram, tenant:, name: "Telegram Bot")
      tool = described_class.new(runtime_context: runtime_context_for(channel), current_channel: channel)
      service = instance_double(Telegram::WebhookSetupService)

      allow(Telegram::WebhookSetupService).to receive(:new).with(channel, host: "example.com").and_return(service)
      allow(service).to receive(:call).and_return(
        Telegram::WebhookSetupService::Result.new(success?: true, message: "Webhook ready"),
      )

      result = tool.execute(action: "setup_webhook")

      expect(result).to include("Action: `setup_webhook`", "Webhook ready")
    end
  end
end
