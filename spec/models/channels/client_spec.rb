# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channels::Client do
  describe ".default_labels" do
    it "uses the provided channel name in the welcome heading" do
      expect(described_class.default_labels(channel_name: "Support Portal")).to include(
        "welcome_heading" => "Welcome to Support Portal",
      )
    end

    it "falls back to the app name when the channel name is blank" do
      expect(described_class.default_labels(channel_name: nil)["welcome_heading"]).to eq("Welcome to Undercover Agents")
    end
  end

  describe ".permitted_params" do
    it "permits only client configuration fields" do
      params = ActionController::Parameters.new(
        channel: {
          title: "Support",
          welcome_message: "Hello",
          footer: "Footer",
          send_button_label: "Launch",
          ignored: "value",
        },
      )

      expect(described_class.permitted_params(params).to_h).to eq(
        "title" => "Support",
        "welcome_message" => "Hello",
        "footer" => "Footer",
        "send_button_label" => "Launch",
      )
    end
  end

  describe "instance behavior" do
    let(:tenant) { create(:tenant) }
    let(:operation) { create(:operation, tenant:) }
    let(:channel) do
      create(
        :channel,
        :client,
        tenant:,
        name: "Support Portal",
        configuration: {
          "title" => "<p>Support Portal</p>",
          "welcome_message" => "Hello there",
          "footer" => "Footer copy",
          "send_button_label" => "Launch",
        },
      )
    end

    it "merges label overrides into the effective label settings" do
      configurator = described_class.new(send_button_label: "Launch", welcome_heading: "Custom heading")

      expect(configurator.effective_label_settings(channel_name: "Support Portal")).to include(
        "send_button_label" => "Launch",
        "welcome_heading" => "Custom heading",
        "new_chat_label" => "New chat",
      )
    end

    it "sanitizes rich text fields while preserving allowed markup" do
      configurator = described_class.new(
        title: "<script>alert(1)</script><p><strong>Safe</strong></p>",
        footer: "<a href=\"https://example.com\" onclick=\"evil()\">Link</a>",
      )

      configurator.valid?

      expect(configurator.title).to eq("alert(1)<p><strong>Safe</strong></p>")
      expect(configurator.footer).to include("href=\"https://example.com\"")
      expect(configurator.footer).not_to include("onclick")
    end

    it "rejects overlong label overrides" do
      configurator = described_class.new(send_button_label: "x" * (described_class::LABEL_LENGTH_LIMIT + 1))

      expect(configurator).not_to be_valid
      expect(configurator.errors["labels.send_button_label"]).to include(
        "is too long (maximum is #{described_class::LABEL_LENGTH_LIMIT} characters)",
      )
    end

    it "builds the client settings payload with labels, agent details, and logo URL" do
      agent = create(:agent, operation:, name: "Support Agent")
      create(:channel_target, channel:, target: agent, default: true)
      channel.logo.attach(io: StringIO.new("logo"), filename: "logo.txt", content_type: "text/plain")

      payload = channel.configurator.settings_payload(channel:)

      expect(payload).to include(
        id: channel.id,
        name: "Support Portal",
        title: "<p>Support Portal</p>",
        welcome_message: "Hello there",
        footer: "Footer copy",
        agent_id: agent.id,
        agent_name: "Support Agent",
      )
      expect(payload[:labels]).to include("send_button_label" => "Launch")
      expect(payload[:logo_url]).to include("logo.txt")
    end

    it "defaults client retry actions to disabled while keeping other message actions enabled" do
      payload = described_class.new.settings_payload(channel:)

      expect(payload[:message_actions]).to include(
        "copy_assistant_response" => true,
        "copy_user_message" => true,
        "retry_assistant_message" => false,
      )
      expect(payload[:retry_assistant_message_enabled]).to be(false)
    end

    it "preserves explicit message action overrides in the settings payload" do
      configurator = described_class.new(
        message_actions_visibility: "always",
        copy_user_message_enabled: false,
      )

      payload = configurator.settings_payload(channel:)

      expect(payload[:message_actions]).to include(
        "visibility" => "always",
        "copy_user_message" => false,
      )
    end

    it "validates message action visibility" do
      configurator = described_class.new(message_actions_visibility: "sometimes")

      expect(configurator).not_to be_valid
      expect(configurator.errors[:message_actions_visibility]).to include("must be one of: always, hover")
    end

    it "returns the shared client partial paths and summary" do
      configurator = described_class.new

      expect(configurator.summary).to eq("Web chat")
      expect(configurator.form_partial_path).to eq(Rails.root.join("app/views/channels/client"))
      expect(configurator.show_partial_path).to eq(Rails.root.join("app/views/channels/client"))
    end
  end
end
