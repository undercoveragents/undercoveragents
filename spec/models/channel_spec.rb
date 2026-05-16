# frozen_string_literal: true

# == Schema Information
#
# Table name: channels
# Database name: primary
#
#  id            :bigint           not null, primary key
#  channel_type  :string           not null
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  connector_id  :bigint
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_channels_on_channel_type        (channel_type)
#  index_channels_on_connector_id        (connector_id)
#  index_channels_on_default             (default)
#  index_channels_on_enabled             (enabled)
#  index_channels_on_slug                (slug) UNIQUE
#  index_channels_on_tenant_id           (tenant_id)
#  index_channels_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe Channel do
  subject(:channel) { build(:channel) }

  around do |example|
    described_class.invalidate_client_settings_cache!
    example.run
    described_class.invalidate_client_settings_cache!
  end

  describe "associations" do
    it { is_expected.to belong_to(:tenant) }
    it { is_expected.to belong_to(:connector).optional }
    it { is_expected.to have_many(:channel_targets).dependent(:destroy) }
    it { is_expected.to have_many(:channel_identities).dependent(:destroy) }
    it { is_expected.to have_many(:channel_conversations).dependent(:destroy) }
    it { is_expected.to have_many(:channel_credentials).dependent(:destroy) }
    it { is_expected.to have_many(:chats).dependent(:nullify) }
    it { is_expected.to have_many(:mission_runs).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:tenant_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:description).is_at_most(500) }
    it { is_expected.to validate_presence_of(:channel_type) }

    it "rejects unregistered channel types" do
      channel.channel_type = "unknown_gateway"

      expect(channel).not_to be_valid
      expect(channel.errors[:channel_type]).to include("is not a registered channel type")
    end

    it "requires the connector to belong to the same tenant" do
      channel.connector = create(:connector, :llm_provider, tenant: create(:tenant))

      expect(channel).not_to be_valid
      expect(channel.errors[:connector]).to include("must belong to the same tenant")
    end

    it "requires connectors to match the channel type requirement" do
      tenant = create(:tenant)
      channel = build(:channel, :client, tenant:, connector: create(:connector, :llm_provider, tenant:))
      configurator_class = Class.new do
        def self.requires_connector_type = "telegram"
      end
      configurator = double(valid?: true)

      allow(configurator).to receive(:class).and_return(configurator_class)
      allow(channel).to receive(:configurator).and_return(configurator)

      expect(channel).not_to be_valid
      expect(channel.errors[:connector]).to include("must be a telegram connector")
    end
  end

  describe "configuration delegation" do
    it "builds the channel configurator from stored JSON" do
      channel = build(:channel, :api, configuration: { "response_mode" => "sync" })

      expect(channel.configurator).to be_a(Channels::Api)
      expect(channel.summary).to eq("All tenant missions / Sync")
    end

    it "serializes normalized configurator attributes before save" do
      channel = create(:channel, :api, configuration: { "response_mode" => "sync", "unused" => "ignored" })

      expect(channel.reload.configuration).to include("response_mode" => "sync")
      expect(channel.configuration).not_to include("unused")
    end

    it "returns nil when configurator resolution raises" do
      channel = build(:channel, :client)

      allow(ChannelPlugin).to receive(:resolve).with("client").and_raise(StandardError)

      expect(channel.configurator).to be_nil
    end
  end

  describe "type metadata" do
    it "falls back to titleized labels and the default icon" do
      channel = build(:channel, channel_type: "custom_gateway")

      expect(channel.type_label).to eq("Custom Gateway")
      expect(channel.type_icon).to eq("fa-solid fa-tower-broadcast")
    end

    it "reports API channels correctly" do
      expect(build(:channel, :api).api_channel?).to be(true)
    end
  end

  describe "targets and payloads" do
    it "returns the default target and client agent when present" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      channel = create(:channel, :client, tenant:)
      fallback_agent = create(:agent, operation:, name: "Fallback Agent")
      default_agent = create(:agent, operation:, name: "Default Agent")
      create(:channel_target, channel:, target: fallback_agent, default: false, position: 1)
      default_target = create(:channel_target, channel:, target: default_agent, default: true, position: 0)

      expect(channel.default_target).to eq(default_target)
      expect(channel.client_agent).to eq(default_agent)
      expect(channel.allowed_target_kinds).to eq(["agent"])
    end

    it "returns nil for settings payloads on non-client channels" do
      channel = build(:channel, :api)

      expect(channel.settings_payload).to be_nil
    end

    it "returns nil for client agents when the default target is a mission" do
      mission = build_stubbed(:mission)
      channel = build(:channel, :client)

      allow(channel).to receive(:default_target).and_return(
        instance_double(ChannelTarget, target_type: "Mission", target: mission),
      )

      expect(channel.client_agent).to be_nil
    end

    it "returns nil for client settings payloads when the configurator is unavailable" do
      channel = build(:channel, :client)

      allow(channel).to receive(:configurator).and_return(nil)

      expect(channel.settings_payload).to be_nil
    end

    it "returns nil for client agents when no default target exists" do
      channel = build(:channel, :client)

      allow(channel).to receive(:default_target).and_return(nil)

      expect(channel.client_agent).to be_nil
    end

    it "raises NoMethodError for unknown delegated methods" do
      expect { build(:channel).unsupported_channel_method }.to raise_error(NoMethodError)
    end

    it "copies configurator validation errors onto the channel" do
      channel = build(:channel, :client)
      configurator_class = Class.new do
        def self.requires_connector_type = nil
      end
      configurator = double(
        valid?: false,
        errors: [double(attribute: :response_mode, message: "can't be blank")],
      )

      allow(configurator).to receive(:class).and_return(configurator_class)
      allow(channel).to receive(:configurator).and_return(configurator)

      expect(channel).not_to be_valid
      expect(channel.errors[:response_mode]).to include("can't be blank")
    end
  end

  describe ".current_client_channel" do
    it "returns nil without a tenant" do
      expect(described_class.current_client_channel(tenant: nil)).to be_nil
      expect(described_class.current_client_settings(tenant: nil)).to be_nil
    end

    it "prefers the default enabled client channel" do
      tenant = create(:tenant)
      preferred = create(:channel, :client, tenant:, default: true, name: "Preferred")
      create(:channel, :client, tenant:, default: false, name: "Secondary")

      expect(described_class.current_client_channel(tenant:)).to eq(preferred)
    end

    it "falls back to the first enabled client channel when no default exists" do
      tenant = create(:tenant)
      first_channel = create(:channel, :client, tenant:, default: false, name: "A Channel")
      create(:channel, :client, tenant:, default: false, name: "B Channel")

      expect(described_class.current_client_channel(tenant:)).to eq(first_channel)
    end

    it "returns the current client settings for the resolved default channel" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      agent = create(:agent, operation:, name: "Support Agent")
      channel = create(:channel, :client, tenant:, default: true, name: "Client Settings",
                                          configuration: { "title" => "Hello" },)
      create(:channel_target, channel:, target: agent, default: true)

      expect(described_class.current_client_settings(tenant:)).to include(name: "Client Settings", title: "Hello")
    end
  end

  describe "private configurator helpers" do
    it "returns the full configuration hash when the configurator class lacks attribute metadata" do
      channel = build(:channel, configuration: { "title" => "Hello" })

      expect(channel.send(:configurator_attributes_for, Class.new)).to eq(title: "Hello")
    end

    it "does not add validation errors when the configurator is already valid" do
      channel = build(:channel, :client)
      configurator_class = Class.new do
        def self.requires_connector_type = nil
      end
      configurator = double(valid?: true)

      allow(configurator).to receive(:class).and_return(configurator_class)
      allow(channel).to receive(:configurator).and_return(configurator)

      channel.valid?

      expect(channel.errors).to be_empty
    end

    it "accepts matching connector types" do
      tenant = create(:tenant)
      channel = build(:channel, tenant:, connector: build(:connector, :telegram, tenant:))
      configurator_class = Class.new do
        def self.requires_connector_type = "telegram"
      end
      configurator = double(valid?: true)

      allow(configurator).to receive(:class).and_return(configurator_class)
      allow(channel).to receive(:configurator).and_return(configurator)

      channel.valid?

      expect(channel.errors[:connector]).to be_empty
    end

    it "applies configurator output before save when a configurator is present" do
      channel = build(:channel, configuration: {})
      configurator = instance_double(Channels::Client, to_configuration: { "title" => "Updated" })

      allow(channel).to receive(:configurator).and_return(configurator)

      channel.send(:apply_configurator_before_save)

      expect(channel.configuration).to eq({ "title" => "Updated" })
    end

    it "leaves configuration unchanged before save when no configurator is present" do
      channel = build(:channel, configuration: { "title" => "Existing" })

      allow(channel).to receive(:configurator).and_return(nil)

      channel.send(:apply_configurator_before_save)

      expect(channel.configuration).to eq({ "title" => "Existing" })
    end

    it "normalizes non-hash configuration payloads" do
      channel = build(:channel)
      channel.configuration = "invalid"

      channel.send(:ensure_configuration)

      expect(channel.configuration).to eq({})
    end
  end
end
