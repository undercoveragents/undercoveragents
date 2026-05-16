# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::PluginHooks do
  describe ".allow_development_webhook_host!" do
    it "adds the tunnel host in development" do
      hosts = []

      described_class.allow_development_webhook_host!(
        env: ActiveSupport::StringInquirer.new("development"),
        tunnel_url: "https://example.ngrok.app",
        hosts:,
      )

      expect(hosts).to eq(["example.ngrok.app"])
    end

    it "does nothing outside development or without a tunnel URL" do
      hosts = []

      described_class.allow_development_webhook_host!(
        env: ActiveSupport::StringInquirer.new("test"),
        tunnel_url: "https://example.ngrok.app",
        hosts:,
      )
      described_class.allow_development_webhook_host!(
        env: ActiveSupport::StringInquirer.new("development"),
        tunnel_url: nil,
        hosts:,
      )

      expect(hosts).to be_empty
    end

    it "does not add a host when development has a blank tunnel URL" do
      hosts = []

      described_class.allow_development_webhook_host!(
        env: ActiveSupport::StringInquirer.new("development"),
        tunnel_url: "",
        hosts:,
      )

      expect(hosts).to be_empty
    end
  end

  describe "plugin reload hook" do
    let(:plugin_path) { Rails.root.join("plugins/telegram/plugin.rb").to_s }
    let(:definition) { UndercoverAgents::PluginSystem::Definition.new("telegram") }

    around do |example|
      original_webhook_url = ENV.fetch("TELEGRAM_WEBHOOK_BASE_URL", nil)
      original_hosts = Rails.application.config.hosts.dup

      example.run
    ensure
      ENV["TELEGRAM_WEBHOOK_BASE_URL"] = original_webhook_url
      Rails.application.config.hosts.clear
      original_hosts.each { |host| Rails.application.config.hosts << host }
    end

    before do
      allow(UndercoverAgents::PluginSystem).to receive(:register) do |_identifier, &block|
        definition.tap do |plugin_definition|
          plugin_definition.instance_eval(&block) if block
        end
      end
    end

    it "registers Telegram as a connector and channel plugin" do
      load plugin_path

      expect(definition.category).to eq([:connector, :channel])
      expect(definition.entry_points).to include(
        { category: :connector, class_name: "Telegram" },
        { category: :channel, class_name: "Telegram" },
      )
    end

    it "adds the configured development webhook host when the plugin file loads" do
      ENV["TELEGRAM_WEBHOOK_BASE_URL"] = "https://example.ngrok.app"
      hosts = []

      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(Rails.application.config).to receive(:hosts).and_return(hosts)

      load plugin_path

      expect(hosts).to include("example.ngrok.app")
    end
  end
end
