# frozen_string_literal: true

module ChannelDesigner
  BASE_EDITABLE_FIELDS = [
    "name",
    "channel_type",
    "description",
    "enabled",
    "default",
    "connector_id",
    "agent_id",
    "agent_ids",
    "mission_id",
    "mission_ids",
    "access_scope",
    "response_mode",
    "callback_url",
  ].freeze
  CLIENT_FIELD_GROUPS = [
    {
      title: "Content",
      fields: {
        "title" => "Brand Title",
        "welcome_message" => "Welcome Message",
        "footer" => "Footer Text",
      },
    },
    {
      title: "Chat Labels",
      fields: {
        "new_chat_label" => "New Chat Button",
        "composer_placeholder" => "Composer Placeholder",
        "sidebar_toggle_label" => "Sidebar Toggle Title",
        "sidebar_open_label" => "Sidebar Open Title",
        "attach_button_label" => "Attach Button",
        "send_button_label" => "Send Button",
        "stop_button_label" => "Stop Button",
        "drop_files_label" => "Drop Files Label",
        "empty_state_title" => "Empty Chat Title",
        "empty_state_body" => "Empty Chat Body",
        "welcome_heading" => "Welcome Heading",
        "welcome_body" => "Welcome Body",
        "no_agent_body" => "No Agent Message",
        "delete_chat_title" => "Delete Chat Button Title",
        "delete_chat_confirm_title" => "Delete Confirmation Title",
        "delete_chat_confirm_message" => "Delete Confirmation Message",
        "delete_chat_confirm_label" => "Delete Confirmation Button",
      },
    },
    {
      title: "Account Menu Labels",
      fields: {
        "profile_settings_label" => "Profile Link",
        "admin_label" => "Admin Link",
        "change_password_label" => "Change Password Link",
        "change_password_dialog_title" => "Change Password Dialog Title",
        "theme_label" => "Theme Toggle",
        "sign_out_label" => "Sign Out Link",
      },
    },
  ].freeze

  class ReadChannelTool < RubyLLM::Tool
    include ChannelLookup

    description "Inspect the current channel configuration or another channel in the current tenant."

    param :channel_id,
          desc: "Optional numeric ID or slug. Omit to inspect the current channel from page context.",
          required: false

    def initialize(runtime_context:, current_channel: nil)
      super()
      @runtime_context = runtime_context
      @current_channel = current_channel
    end

    def name = "read_channel"

    def execute(channel_id: nil)
      channel = resolve_channel(channel_id)
      return missing_channel_message if channel.nil?

      [
        summary_section(channel),
        targets_section(channel),
        configuration_section(channel),
        client_editable_fields_section(channel),
        editable_fields_section(channel),
      ].join("\n\n")
    rescue ActiveRecord::RecordNotFound => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading channel: #{e.message}"
    end

    private

    def summary_section(channel)
      preview_path = channel_preview_path(channel)

      [
        "## Channel",
        "- ID: `#{channel.id}`",
        "- Name: #{channel.name}",
        "- Slug: `#{channel.slug}`",
        "- Type: `#{channel.channel_type}` — #{channel.type_label}",
        "- Default: #{channel.default?}",
        "- Enabled: #{channel.enabled?}",
        ("- Connector ID: `#{channel.connector_id}`" if channel.connector_id.present?),
        ("- Preview path: `#{preview_path}`" if preview_path.present?),
      ].compact.join("\n")
    end

    def targets_section(channel)
      targets = channel.channel_targets.includes(:target).ordered
      return "## Targets\n- None" if targets.empty?

      lines = ["## Targets"]
      targets.each do |target|
        lines << target_line(target)
      end
      lines.join("\n")
    end

    def configuration_section(channel)
      payload = channel.configuration.presence || {}
      title = normalized_settings_payload(channel)["title"]
      payload = payload.merge("title" => title) if channel.client_channel? && title.present?

      "## Current Configuration\n```json\n#{JSON.pretty_generate(payload)}\n```"
    end

    def client_editable_fields_section(channel)
      return unless channel.client_channel?

      lines = [
        "## Client Editable Fields",
        [
          "Use these exact attribute keys with `manage_record(attributes: ...)`.",
          "Label fields show the current effective value; `default` means no custom override is stored.",
        ].join(" "),
      ]

      CLIENT_FIELD_GROUPS.each do |group|
        lines << "### #{group.fetch(:title)}"

        group.fetch(:fields).each do |field, label|
          lines << "- `#{field}` (#{label})#{client_field_value_suffix(channel, field)}"
        end
      end

      lines.join("\n")
    end

    def editable_fields_section(channel)
      lines = [
        "## Editable Attribute Keys",
        *BASE_EDITABLE_FIELDS.map { |field| "- `#{field}`" },
        "- Use `list_resources(kind: \"agents\")` to resolve exact `agent_id` and `agent_ids` values.",
        "- Use `list_resources(kind: \"missions\")` to resolve exact `mission_id` and `mission_ids` values.",
        "- Use `navigate_to_page(resource: \"channel\", page: \"preview\", ...)` only for client channels.",
        "- Channel type is immutable after create.",
      ]
      if channel.client_channel?
        lines << "- All client-channel content and label keys are listed in `## Client Editable Fields` above."
      end
      if channel.api_channel?
        lines << "- API channel token values are not returned by `read_channel`; " \
                 "use `manage_channel_action(action: \"regenerate_token\")` when you must rotate them."
      end

      lines.join("\n")
    end

    def channel_preview_path(channel)
      return unless channel.client_channel?

      Rails.application.routes.url_helpers.admin_channel_path(channel, view: :preview)
    end

    def target_line(target)
      default_suffix = target.default? ? " (default)" : nil

      "- `#{target.target_type}` `#{target.target_id}` — #{target.name}#{default_suffix}"
    end

    def client_field_value_suffix(channel, field)
      value = client_field_value(channel, field)
      value_note = value.present? ? JSON.generate(value.to_s) : "(blank)"

      return " — current: #{value_note}" unless client_label_field?(field)

      raw_value = channel.configuration.to_h.deep_stringify_keys[field]
      source = raw_value.present? ? "custom" : "default"

      " — current (#{source}): #{value_note}"
    end

    def client_field_value(channel, field)
      payload = normalized_settings_payload(channel)

      if client_label_field?(field)
        payload.dig("labels", field)
      else
        payload[field]
      end
    end

    def normalized_settings_payload(channel)
      (channel.settings_payload || {}).to_h.deep_stringify_keys
    end

    def client_label_field?(field)
      @client_label_fields ||= ClientConfiguration::LABEL_FIELDS.to_set(&:to_s)
      @client_label_fields.include?(field)
    end
  end
end
