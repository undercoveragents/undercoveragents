# frozen_string_literal: true

module ChannelDesigner
  class ManageChannelActionTool < RubyLLM::Tool
    include ChannelLookup
    include CurrentPageRefreshable
    include PolicyAuthorizable

    ACTIONS = {
      "regenerate_token" => :regenerate_token,
      "setup_webhook" => :setup_webhook,
    }.freeze

    description(
      "Run channel admin actions that are not covered by generic CRUD, such as token rotation or webhook setup.",
    )

    param :action,
          desc: "Channel action to run. Supported values: 'regenerate_token' and 'setup_webhook'."

    param :channel_id,
          desc: "Optional numeric ID or slug. Omit to act on the current channel from page context.",
          required: false

    def initialize(runtime_context:, current_channel: nil)
      super()
      @runtime_context = runtime_context
      @current_channel = current_channel
    end

    def name = "manage_channel_action"

    def execute(action:, channel_id: nil)
      normalized_action = ACTIONS[action.to_s]
      return "Error: Unknown action '#{action}'. Use regenerate_token or setup_webhook." unless normalized_action

      channel = resolve_channel(channel_id)
      return missing_channel_message if channel.nil?

      case normalized_action
      when :regenerate_token
        regenerate_token(channel)
      when :setup_webhook
        setup_webhook(channel)
      end
    rescue ActiveRecord::RecordNotFound, ArgumentError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing channel action: #{e.message}"
    end

    private

    def regenerate_token(channel)
      authorize_policy!(channel, :regenerate_token?, user: @runtime_context.user)
      raise ArgumentError, "Channel '#{channel.name}' does not use API bearer tokens." unless channel.api_channel?

      raw_token = channel.channel_credentials.first_or_create!(
        name: "Primary token",
        credential_type: "bearer_token",
      ).regenerate_token!
      refreshed = broadcast_current_page_refresh?

      [
        "Channel action completed.",
        "- Channel: #{channel.name} (`#{channel.id}`)",
        "- Action: `regenerate_token`",
        "- New token: `#{raw_token}`",
        "- Result: API token regenerated successfully.",
        ("Current page refresh started to show the saved channel." if refreshed),
      ].compact.join("\n")
    end

    def setup_webhook(channel)
      authorize_policy!(channel, :setup_webhook?, user: @runtime_context.user)
      raise ArgumentError, "Channel '#{channel.name}' does not support webhook setup." unless telegram_channel?(channel)

      result = Telegram::WebhookSetupService.new(channel, host: resolved_host).call
      return "Error: #{result.message}" unless result.success?

      refreshed = broadcast_current_page_refresh?

      [
        "Channel action completed.",
        "- Channel: #{channel.name} (`#{channel.id}`)",
        "- Action: `setup_webhook`",
        "- Result: #{result.message}",
        ("Current page refresh started to show the saved channel." if refreshed),
      ].compact.join("\n")
    end

    def telegram_channel?(channel)
      defined?(Channels::Telegram) &&
        defined?(Telegram::WebhookSetupService) &&
        channel.channel_type == Channels::Telegram.key
    end

    def resolved_host
      url_options = Rails.application.routes.default_url_options.presence ||
                    Rails.application.config.action_mailer.default_url_options || {}
      url_options[:host]
    end
  end
end
