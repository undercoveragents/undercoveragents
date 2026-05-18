# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelDesigner::ReadChannelTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:agent_record) { create(:agent, operation:, name: "Support Agent", model_id: "gpt-4.1") }
  let(:client_channel) do
    create(
      :channel,
      :client,
      tenant:,
      default: true,
      name: "Support Portal",
      configuration: {
        "title" => "<p>Support Portal</p>",
        "welcome_message" => "<p>Welcome!</p>",
        "footer" => "<p>Footer</p>",
        "new_chat_label" => "Start now",
      },
    ).tap do |channel|
      create(:channel_target, channel:, target: agent_record, default: true)
    end
  end
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation:,
    )
  end

  describe "#name" do
    it "returns read_channel" do
      expect(described_class.new(runtime_context:).name).to eq("read_channel")
    end
  end

  describe "#execute" do
    it "reads the current channel configuration and editable fields" do
      result = described_class.new(runtime_context:, current_channel: client_channel).execute

      expect(result).to include(
        "## Channel",
        "Support Portal",
        "client",
        "## Targets",
        "Support Agent",
        "## Current Configuration",
        '"title": "<p>Support Portal</p>"',
        "## Client Editable Fields",
        '`new_chat_label` (New Chat Button) — current (custom): "Start now"',
        '`theme_label` (Theme Toggle) — current (default): "Theme"',
        "`profile_settings_label` (Profile Link)",
        "## Editable Attribute Keys",
        "`channel_type`",
        "`agent_id`",
      )
    end

    it "finds a channel by id inside the current tenant" do
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_channel = create(:channel, :api, tenant: foreign_tenant, name: "Foreign Channel")
      tool = described_class.new(runtime_context:)
      missing_channel_error = "Error: Channel '#{foreign_channel.id}' was not found."

      expect(tool.execute(channel_id: client_channel.id)).to include("Support Portal")
      expect(tool.execute(channel_id: foreign_channel.id)).to eq(missing_channel_error)
    end

    it "finds a channel by unique name inside the current tenant" do
      tool = described_class.new(runtime_context:)

      expect(tool.execute(channel_id: client_channel.name)).to include("Support Portal")
    end

    it "includes the API token note for API channels" do
      api_channel = create(:channel, :api, tenant:, name: "Public API")
      create(:channel_credential, channel: api_channel, name: "Primary Token")

      result = described_class.new(runtime_context:, current_channel: api_channel).execute

      expect(result).to include("API channel token values are not returned")
    end

    it "includes connector details when the channel is connector-backed" do
      connector = create(:connector, :telegram, tenant:)
      api_channel = create(:channel, :api, tenant:, connector:, name: "Telegram API")

      result = described_class.new(runtime_context:, current_channel: api_channel).execute

      expect(result).to include("- Connector ID: `#{connector.id}`")
    end

    it "merges the client title from the settings payload into the configuration output" do
      tool = described_class.new(runtime_context:, current_channel: client_channel)

      allow(client_channel).to receive(:settings_payload).and_return({ "title" => "Support Portal Title" })

      expect(tool.execute).to include('"title": "Support Portal Title"')
    end

    it "rescues unexpected errors while rendering" do
      tool = described_class.new(runtime_context:, current_channel: client_channel)
      allow(tool).to receive(:summary_section).and_raise(StandardError, "boom")

      expect(tool.execute).to eq("Error reading channel: boom")
    end

    it "returns a helpful message when there is no current channel" do
      result = described_class.new(runtime_context:).execute

      expect(result).to eq("No current channel is available. Open a channel page or pass channel_id.")
    end
  end

  describe "private helpers" do
    it "omits the default suffix for non-default targets" do
      target = build(:channel_target, default: false)
      tool = described_class.new(runtime_context:, current_channel: client_channel)

      expect(tool.send(:target_line, target)).not_to include("(default)")
    end

    it "uses the runtime context tenant when available" do
      tool = described_class.new(runtime_context:, current_channel: client_channel)

      expect(tool.send(:tenant)).to eq(tenant)
    end

    it "prefers the runtime context operation when available" do
      other_operation = create(:operation, tenant:)
      other_channel = create(:channel, :api, tenant:, operation: other_operation, name: "Other Channel")
      tool = described_class.new(runtime_context:, current_channel: other_channel)

      expect(tool.send(:operation)).to eq(operation)
    end

    it "falls back to the current channel operation when runtime context is missing" do
      tool = described_class.new(runtime_context: nil, current_channel: client_channel)

      expect(tool.send(:operation)).to eq(client_channel.operation)
    end

    it "falls back to Current.operation when runtime and current channel operations are unavailable" do
      Current.operation = operation
      tool = described_class.new(runtime_context: nil)

      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect(tool.send(:operation)).to eq(operation)
    ensure
      Current.reset
    end

    it "returns nil when no operation source is available" do
      tool = described_class.new(runtime_context: nil)

      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect(tool.send(:operation)).to be_nil
    end

    it "falls back to the tenant default operation when no other operation source is available" do
      fallback_tenant = create(:tenant).tap(&:ensure_core_resources!)
      tool = described_class.new(runtime_context: nil)

      allow(Tenant).to receive(:default_tenant).and_return(fallback_tenant)

      expect(tool.send(:operation)).to eq(fallback_tenant.default_operation)
    end

    it "falls back to the current channel tenant when runtime context is missing" do
      tool = described_class.new(runtime_context: nil, current_channel: client_channel)

      expect(tool.send(:tenant)).to eq(client_channel.tenant)
    end

    it "falls back to the default tenant when runtime and current channel tenants are unavailable" do
      fallback_tenant = create(:tenant)
      tool = described_class.new(runtime_context: nil)

      allow(Tenant).to receive(:default_tenant).and_return(fallback_tenant)

      expect(tool.send(:tenant)).to eq(fallback_tenant)
    end
  end
end
