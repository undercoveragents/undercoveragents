# frozen_string_literal: true

require_relative "app/services/telegram/plugin_hooks"

# Allow the configured tunnel host (e.g. ngrok) derived from TELEGRAM_WEBHOOK_BASE_URL.
require "uri"
Telegram::PluginHooks.allow_development_webhook_host!

UndercoverAgents::PluginSystem.register("telegram") do
  name "Telegram"
  version "1.0.0"
  author "Undercover Agents"
  description "Telegram connector and channel — send and receive messages via Telegram."
  icon "fa-brands fa-telegram"
  category [:connector, :channel]

  add_connector "Telegram"
  add_channel "Telegram"
end
