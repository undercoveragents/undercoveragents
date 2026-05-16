# frozen_string_literal: true

module Telegram
  module PluginHooks
    module_function

    def allow_development_webhook_host!(env: Rails.env, tunnel_url: ENV.fetch("TELEGRAM_WEBHOOK_BASE_URL", nil),
                                        hosts: Rails.application.config.hosts)
      return unless env.development? && tunnel_url.present?

      hosts << URI.parse(tunnel_url).host
    end
  end
end
