# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Channels" do
  let(:agent) { create(:agent, operation: default_operation) }
  let(:mission) { create(:mission, operation: default_operation) }

  describe "GET /admin/channels" do
    it "lists channels for the current operation" do
      create(:channel, tenant: default_tenant, operation: default_operation, name: "Support Channel")
      create(
        :channel,
        tenant: default_tenant,
        operation: create(:operation, tenant: default_tenant),
        name: "Other Operation Channel",
      )

      get admin_channels_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Support Channel")
      expect(response.body).not_to include("Other Operation Channel")
    end

    it "renders each channel card as a single link without inline action buttons" do
      channel = create(:channel, :api, tenant: default_tenant, name: "Support API")
      create(:channel_target, :mission, channel:, target: mission, default: true)

      get admin_channels_path

      document = response.parsed_body
      card = document.at_css(%(a.entity-card--interactive[href="#{admin_channel_path(channel)}"]))

      expect(card).to be_present
      expect(card.css(".btn")).to be_empty
    end
  end

  describe "GET /admin/channels/new" do
    it "renders the channel type chooser when no type is requested", :aggregate_failures do
      get new_admin_channel_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Choose Channel Type")
      expect(response.body).to include("Forms")
      expect(response.body).to include("Slack")
      expect(response.body).to include("WhatsApp")
      expect(response.body).to include("Teams")
      expect(response.body).to include("Coming soon")
      expect(response.body).not_to include("Available now")
      expect(response.body).not_to include("Planned future channel")
      expect(response.body).not_to include("Choose Client")
    end

    it "renders the new form with the requested channel type" do
      get new_admin_channel_path(type: "api")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Channel")
      expect(response.body).to include("API Settings")
      expect(response.body).not_to include(%(>Type<))
    end

    it "returns to the channel type chooser for invalid type params" do
      get new_admin_channel_path(type: "unknown")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Choose Channel Type")
    end
  end

  describe "POST /admin/channels" do
    let(:client_params) do
      {
        channel: {
          name: "Client Channel",
          description: "Branded chat",
          channel_type: "client",
          enabled: "1",
          default: "1",
          title: "Client title",
          welcome_message: "Welcome aboard",
          footer: "Footer copy",
        },
        channel_target: { target_kind: "agent", agent_id: agent.id },
      }
    end

    it "creates a client channel with an agent target" do
      expect do
        post admin_channels_path, params: client_params
      end.to change(Channel, :count).by(1)
         .and change(ChannelTarget, :count).by(1)

      expect(response).to redirect_to(admin_channel_path(Channel.last))
    end

    it "persists client channel details" do
      post admin_channels_path, params: client_params

      channel = Channel.last
      expect(channel).to have_attributes(name: "Client Channel", channel_type: "client", default: true)
      expect(channel.configuration).to include("title" => "Client title", "welcome_message" => "Welcome aboard")
      expect(channel.channel_targets.first.target).to eq(agent)
      expect(channel.channel_credentials).to be_empty
    end

    it "keeps one default channel per type" do
      existing_default = create(:channel, :client, tenant: default_tenant, default: true)

      post admin_channels_path, params: client_params

      expect(existing_default.reload.default?).to be(false)
      expect(Channel.last.default?).to be(true)
    end

    it "creates an API channel credential and exposes the generated token once" do
      expect do
        post admin_channels_path, params: {
          channel: { name: "API Channel", channel_type: "api", response_mode: "sync" },
          channel_target: { target_kind: "mission", mission_id: mission.id },
        }
      end.to change(ChannelCredential, :count).by(1)

      channel = Channel.last
      credential = channel.channel_credentials.first
      expect(credential).to be_bearer_token
      expect(channel.channel_targets.first.target).to eq(mission)
      follow_redirect!
      expect(response.body).to include("Channel Token Generated")
      expect(response.body).to include("ch_")
    end

    it "re-renders the form with errors for invalid channel params" do
      post admin_channels_path, params: { channel: { name: "", channel_type: "client" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("error")
    end

    it "re-renders the form when the channel type is invalid" do
      post admin_channels_path, params: { channel: { name: "Invalid", channel_type: "unknown" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("registered channel type")
    end

    it "creates scoped API channels with selected agents and missions" do
      extra_agent = create(:agent, operation: default_operation, name: "Secondary Agent")
      extra_mission = create(:mission, operation: default_operation, name: "Secondary Mission")

      post admin_channels_path, params: {
        channel: { name: "Scoped API", channel_type: "api", access_scope: "scoped" },
        channel_target: {
          target_kind: "agent",
          agent_ids: [agent.id, extra_agent.id],
          mission_ids: [mission.id, extra_mission.id],
        },
      }

      channel = Channel.last
      expect(channel.channel_targets.where(target_type: "Agent").pluck(:target_id))
        .to contain_exactly(agent.id, extra_agent.id)
      expect(channel.channel_targets.where(target_type: "Mission").pluck(:target_id))
        .to contain_exactly(mission.id, extra_mission.id)
    end

    it "creates scoped API channels with no mission targets when mission ids are omitted" do
      post admin_channels_path, params: {
        channel: { name: "Agent Only API", channel_type: "api", access_scope: "scoped" },
        channel_target: { target_kind: "agent", agent_ids: [agent.id], mission_ids: [""] },
      }

      channel = Channel.last
      expect(channel.channel_targets.where(target_type: "Agent").pluck(:target_id)).to eq([agent.id])
      expect(channel.channel_targets.where(target_type: "Mission")).to be_empty
    end
  end

  describe "GET /admin/channels/:id" do
    let(:channel) { create(:channel, :api, tenant: default_tenant, name: "Webhook API") }

    before do
      create(:channel_target, :mission, channel:, target: mission, default: true)
      create(:channel_credential, channel:, name: "Primary token")
    end

    it "shows channel details" do
      get admin_channel_path(channel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Webhook API")
      expect(response.body).to include("Token")
      expect(response.body).to include(mission.name)
    end
  end

  describe "GET /admin/channels/:id/edit" do
    it "renders the edit form" do
      channel = create(:channel, :api, tenant: default_tenant)
      create(:channel_target, :mission, channel:, target: mission, default: true)

      get edit_admin_channel_path(channel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Channel")
      expect(response.body).to include("API Settings")
      expect(response.body).not_to include(%(>Type<))
    end
  end

  describe "PATCH /admin/channels/:id" do
    let(:channel) { create(:channel, :api, tenant: default_tenant, name: "Old API") }

    before do
      create(:channel_credential, channel:, name: "Primary token")
      create(:channel_target, channel:, target: agent, default: true)
    end

    it "updates the channel without creating another credential" do
      expect do
        patch admin_channel_path(channel), params: {
          channel: { name: "Updated API", response_mode: "sync", callback_url: "https://example.com/hook" },
          channel_target: { target_kind: "mission", mission_id: mission.id },
        }
      end.not_to change(ChannelCredential, :count)

      expect(response).to redirect_to(admin_channel_path(channel.reload))
      expect(channel.reload.name).to eq("Updated API")
      expect(channel.configuration).to include("response_mode" => "sync", "callback_url" => "https://example.com/hook")
      expect(channel.channel_targets.first.target).to eq(mission)
    end

    it "re-renders the edit form with errors" do
      patch admin_channel_path(channel), params: { channel: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("error")
    end

    it "clears the API channel target when mission selection is blank" do
      api_channel = create(
        :channel,
        :api,
        tenant: default_tenant,
        name: "Lead API",
        configuration: { "access_scope" => "scoped" },
      )
      create(:channel_target, :mission, channel: api_channel, target: mission, default: true)

      patch admin_channel_path(api_channel), params: {
        channel: { name: "Lead API", access_scope: "scoped" },
        channel_target: { target_kind: "mission", mission_id: "" },
      }

      expect(response).to redirect_to(admin_channel_path(api_channel))
      expect(api_channel.reload.channel_targets).to be_empty
    end
  end

  describe "GET /admin/channels/:id?view=preview" do
    it "builds a preview chat when none exists" do
      user = create(:user, :admin, tenant: default_tenant)
      sign_in(user)
      create(:model, model_id: agent.model_id, provider: "openai")
      channel = create(:channel, :client, tenant: default_tenant, name: "Preview Client")
      create(:channel_target, channel:, target: agent, default: true)

      expect do
        get admin_channel_path(channel, view: :preview)
      end.to change(Chat, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Channel Preview")
      expect(response.body).to include("Preview Client")
    end

    it "reuses the requested preview chat when chat_id is provided" do
      user = create(:user, :admin, tenant: default_tenant)
      sign_in(user)
      channel = create(:channel, :client, tenant: default_tenant, name: "Preview Client")
      create(:channel_target, channel:, target: agent, default: true)
      preview_chat = create(:chat, :user_context, user:, agent:, channel:, title: "Existing Preview")
      create(:message, chat: preview_chat, role: :assistant, content: "Preview content")

      expect do
        get admin_channel_path(channel, view: :preview, chat_id: preview_chat.id)
      end.not_to change(Chat, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Preview content")
    end
  end

  describe "custom channel targets" do
    before do
      stub_const("Channels::WebhookRelay", Class.new do
        include UndercoverAgents::PluginSystem::Configurator
        include ChannelPlugin

        key "webhook_relay"
        label "Webhook Relay"
        icon "fa-solid fa-wave-square"
        description "Relay requests to a target."
        target_kinds ["agent", "mission"]
      end,)

      ChannelPlugin.register(
        "webhook_relay",
        "Channels::WebhookRelay",
        label: "Webhook Relay",
        icon: "fa-solid fa-wave-square",
        description: "Relay requests to a target.",
        source: :app,
      )
    end

    after do
      ChannelPlugin.reset!
      UndercoverAgents::PluginSystem.register_channel_types!
    end

    it "leaves generic channels without a default target when none is selected" do
      post admin_channels_path, params: {
        channel: { name: "Untargeted Relay", channel_type: "webhook_relay" },
        channel_target: { target_kind: "agent", agent_id: "" },
      }

      expect(Channel.last.channel_targets).to be_empty
    end

    it "creates a generic channel with an agent default target" do
      post admin_channels_path, params: {
        channel: { name: "Agent Relay", channel_type: "webhook_relay" },
        channel_target: { target_kind: "agent", agent_id: agent.id },
      }

      expect(Channel.last.channel_targets.first.target).to eq(agent)
    end

    it "updates a generic channel to use a mission default target" do
      channel = create(:channel, tenant: default_tenant, name: "Mission Relay", channel_type: "webhook_relay")
      create(:channel_target, channel:, target: agent, default: true)

      patch admin_channel_path(channel), params: {
        channel: { name: "Mission Relay" },
        channel_target: { target_kind: "mission", mission_id: mission.id },
      }

      expect(channel.reload.channel_targets.first.target).to eq(mission)
    end
  end

  describe "DELETE /admin/channels/:id" do
    it "deletes the channel" do
      channel = create(:channel, tenant: default_tenant)

      expect do
        delete admin_channel_path(channel)
      end.to change(Channel, :count).by(-1)

      expect(response).to redirect_to(admin_channels_path)
    end
  end

  describe "PATCH /admin/channels/:id/toggle" do
    it "toggles the enabled status" do
      channel = create(:channel, tenant: default_tenant, enabled: true)

      patch toggle_admin_channel_path(channel)

      expect(channel.reload.enabled?).to be(false)
      expect(response).to redirect_to(admin_channels_path)
    end
  end

  describe "POST /admin/channels/:id/regenerate_token" do
    it "regenerates an existing primary credential" do
      channel = create(:channel, :api, tenant: default_tenant)
      credential = create(:channel_credential, channel:, name: "Primary token")
      old_digest = credential.token_digest

      post regenerate_token_admin_channel_path(channel)

      expect(credential.reload.token_digest).not_to eq(old_digest)
      expect(response).to redirect_to(admin_channel_path(channel))
      follow_redirect!
      expect(response.body).to include("ch_")
    end

    it "creates a primary credential when none exists" do
      channel = create(:channel, :api, tenant: default_tenant)

      expect do
        post regenerate_token_admin_channel_path(channel)
      end.to change(ChannelCredential, :count).by(1)

      expect(channel.channel_credentials.first).to be_bearer_token
    end
  end
end
