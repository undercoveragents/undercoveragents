# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelsHelper do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:agent) { create(:agent, operation:) }
  let(:mission) { create(:mission, operation:) }

  describe "channel show helpers" do
    let(:channel_policy) do
      instance_double(
        ChannelPolicy,
        show?: true,
        update?: true,
        toggle?: true,
        regenerate_token?: true,
        destroy?: true,
      )
    end

    before do
      allowed_policy = channel_policy
      helper.define_singleton_method(:policy) { |_| allowed_policy }
    end

    it "returns the ordered primary credential" do
      channel = create(:channel, :api, tenant:)
      second = create(:channel_credential, channel:, name: "Z Token")
      first = create(:channel_credential, channel:, name: "A Token")

      expect(helper.channel_primary_credential(channel)).to eq(first)
      expect(helper.channel_primary_credential(channel)).not_to eq(second)
    end

    it "builds show metadata for default active channels" do
      channel = build(:channel, :client, tenant:, default: true, enabled: true)
      rendered = helper.channel_show_meta(channel).join

      expect(rendered).to include("Client")
      expect(rendered).to include("Default")
      expect(rendered).to include("Active")
      expect(rendered).to include("badge-success")
    end

    it "renders disabled metadata for non-default channels" do
      channel = build(:channel, :client, tenant:, default: false, enabled: false)
      rendered = helper.channel_show_meta(channel).join

      expect(rendered).to include("Disabled")
      expect(rendered).to include("badge-danger")
      expect(rendered).not_to include("Default")
    end

    it "builds channel show actions for a client preview with a credential" do
      channel = create(:channel, :client, tenant:, enabled: true)
      credential = create(:channel_credential, channel: create(:channel, :api, tenant:))
      actions = helper.channel_show_actions(channel, credential:)

      expect(actions.pluck(:label)).to eq(
        ["Preview", "Edit", "Disable", "Regenerate Token", "Delete"],
      )
      expect(actions.first[:url]).to eq(admin_channel_path(channel, view: :preview))
      expect(actions.third[:icon]).to eq("fa-solid fa-toggle-on")
      expect(actions.fourth[:method]).to eq(:post)
    end

    it "omits preview and token actions when unavailable and switches toggle copy for disabled channels" do
      channel = create(:channel, :api, tenant:, enabled: false)
      limited_policy = instance_double(
        ChannelPolicy,
        show?: false,
        update?: true,
        toggle?: true,
        regenerate_token?: false,
        destroy?: true,
      )

      restricted_policy = limited_policy
      helper.define_singleton_method(:policy) { |_| restricted_policy }

      actions = helper.channel_show_actions(channel, credential: nil)

      expect(actions.pluck(:label)).to eq(["Edit", "Enable", "Delete"])
      expect(actions.second[:icon]).to eq("fa-solid fa-toggle-off")
    end

    it "returns no actions when every policy check is denied" do
      channel = create(:channel, :client, tenant:, enabled: true)
      denied_policy = instance_double(
        ChannelPolicy,
        show?: false,
        update?: false,
        toggle?: false,
        regenerate_token?: false,
        destroy?: false,
      )
      helper.define_singleton_method(:policy) { |_| denied_policy }

      expect(helper.channel_show_actions(channel, credential: nil)).to eq([])
    end

    it "returns the default target path for agent and mission targets" do
      agent_channel = create(:channel, :client, tenant:, operation:)
      mission_channel = create(:channel, :api, tenant:, operation:)
      create(:channel_target, channel: agent_channel, target: agent, default: true)
      create(:channel_target, :mission, channel: mission_channel, target: mission, default: true)

      expect(helper.channel_default_target_path(agent_channel)).to eq(admin_agent_path(agent))
      expect(helper.channel_default_target_path(mission_channel)).to eq(admin_mission_path(mission))
      expect(helper.channel_default_target_path(build(:channel, :client, tenant:))).to be_nil
    end
  end
end
