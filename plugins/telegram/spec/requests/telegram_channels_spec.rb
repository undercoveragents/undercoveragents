# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telegram channels", :unauthenticated do
  let(:admin_user) { create(:user, :admin) }
  let(:tenant) { admin_user.tenant }
  let(:operation) { tenant.default_operation }
  let(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let(:agent) { create(:agent, operation:, model_id: model.model_id, enabled: true, selectable: true) }
  let!(:connector) do
    create(:connector, :telegram, :enabled, tenant:, name: "Telegram Connector", bot_username: "ops_bot")
  end

  before { sign_in(admin_user) }

  it "renders the Telegram channel form" do
    get new_admin_channel_path(type: Channels::Telegram.key)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Telegram Connector")
    expect(response.body).to include("Stream partial replies")
  end

  it "creates a Telegram channel with its default agent target" do
    expect do
      post admin_channels_path, params: {
        channel: {
          name: "Operations Bot",
          channel_type: Channels::Telegram.key,
          connector_id: connector.id,
          welcome_message: "Hi from Telegram",
          max_history_messages: 25,
          streaming_enabled: "1",
        },
        channel_target: { target_kind: "agent", agent_id: agent.id },
      }
    end.to change(Channel, :count).by(1)

    channel = Channel.order(:id).last

    expect(channel.channel_type).to eq(Channels::Telegram.key)
    expect(channel.connector).to eq(connector)
    expect(channel.default_target&.target).to eq(agent)
    expect(channel.welcome_message).to eq("Hi from Telegram")
  end

  it "shows Telegram channel details" do
    channel = create(:channel, :telegram, tenant:, connector:, name: "Ops Bot")
    create(:channel_target, channel:, target: agent, default: true)

    get admin_channel_path(channel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Telegram Channel")
    expect(response.body).to include("Setup Webhook")
    expect(response.body).to include("Ops Bot")
  end

  it "registers the Telegram webhook from the channel page" do
    channel = create(:channel, :telegram, tenant:, connector:)
    service = instance_double(
      Telegram::WebhookSetupService,
      call: Telegram::WebhookSetupService::Result.new(success?: true, message: "registered"),
    )
    allow(Telegram::WebhookSetupService).to receive(:new).and_return(service)

    post setup_telegram_webhook_admin_channel_path(channel)

    expect(response).to redirect_to(admin_channel_path(channel))
    expect(flash[:notice]).to eq("registered")
  end

  it "shows the webhook setup failure on the channel page" do
    channel = create(:channel, :telegram, tenant:, connector:)
    service = instance_double(
      Telegram::WebhookSetupService,
      call: Telegram::WebhookSetupService::Result.new(success?: false, message: "failed"),
    )
    allow(Telegram::WebhookSetupService).to receive(:new).and_return(service)

    post setup_telegram_webhook_admin_channel_path(channel)

    expect(response).to redirect_to(admin_channel_path(channel))
    expect(flash[:alert]).to eq("failed")
  end
end
