# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Telegram profile links", :unauthenticated do
  let(:user) { create(:user) }
  let(:tenant) { user.tenant }
  let(:operation) { tenant.ensure_core_resources!.default_operation }
  let(:model) { create(:model, model_id: "gpt-4.1", provider: "openai") }
  let(:agent) { create(:agent, operation:, model_id: model.model_id, enabled: true, selectable: true) }
  let(:channel) { create(:channel, :telegram, tenant:, operation:, name: "Support Bot") }

  before do
    create(:channel_target, channel:, target: agent, default: true)
    sign_in(user)
  end

  it "renders the Telegram channel profile panel" do
    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Telegram Channels")
    expect(response.body).to include("Support Bot")
    expect(response.body).to include("Link Telegram Account")
  end

  it "creates a link token and shows it on the redirected profile page" do
    post generate_telegram_channel_link_token_profile_path(channel)

    expect(response).to redirect_to(profile_path)
    expect(Channels::TelegramLinkRequest.find_by(channel:, user:)).to be_present

    token = flash[:telegram_link_tokens][channel.id.to_s]
    expect(token).to be_present

    follow_redirect!

    expect(response.body).to include("/link #{token}")
  end

  it "renders the pending-token state when a link request exists without a flash token" do
    create(:telegram_link_request, channel:, user:)

    get profile_path

    expect(response.body).to include("token is pending")
  end

  it "renders the linked-account state" do
    create(
      :channel_identity,
      channel:,
      user:,
      external_user_id: "123456",
      external_username: "telegram_user",
      linked_at: Time.current,
    )

    get profile_path

    expect(response.body).to include("telegram_user")
    expect(response.body).to include("Unlink Telegram")
  end

  it "unlinks the Telegram account for a channel" do
    create(:channel_identity, channel:, user:, external_user_id: "123456", linked_at: Time.current)
    create(:telegram_link_request, channel:, user:)

    delete unlink_telegram_channel_profile_path(channel)

    expect(response).to redirect_to(profile_path)
    expect(channel.channel_identities.where(user:)).to be_empty
    expect(Channels::TelegramLinkRequest.find_by(channel:, user:)).to be_nil
  end

  it "shows the error message when token generation fails" do
    allow(Channels::TelegramLinkRequest).to receive(:issue!).and_raise(StandardError, "token error")

    post generate_telegram_channel_link_token_profile_path(channel)

    expect(response).to redirect_to(profile_path)
    expect(flash[:alert]).to eq("token error")
  end
end
