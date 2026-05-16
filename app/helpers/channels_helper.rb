# frozen_string_literal: true

module ChannelsHelper
  def channel_primary_credential(channel)
    channel.channel_credentials.ordered.first
  end

  def channel_show_meta(channel)
    [
      tag.span(channel.type_label, class: "badge badge-neutral"),
      (tag.span("Default", class: "badge badge-accent") if channel.default?),
      tag.span(
        channel.enabled? ? "Active" : "Disabled",
        class: channel.enabled? ? "badge badge-success" : "badge badge-danger",
      ),
    ].compact
  end

  def channel_show_actions(channel, credential:)
    [
      channel_preview_action(channel),
      channel_edit_action(channel),
      channel_toggle_action(channel),
      channel_regenerate_token_action(channel, credential),
      channel_delete_action(channel),
    ].compact
  end

  def channel_default_target_path(channel)
    target = channel.default_target
    return unless target

    target.target_kind == "agent" ? admin_agent_path(target.target) : admin_mission_path(target.target)
  end

  private

  def channel_preview_action(channel)
    return unless channel.client_channel? && policy(channel).show?

    {
      label: "Preview",
      url: admin_channel_path(channel, view: :preview),
      icon: "fa-solid fa-eye",
      style: :secondary,
    }
  end

  def channel_edit_action(channel)
    return unless policy(channel).update?

    {
      label: "Edit",
      url: edit_admin_channel_path(channel),
      icon: "fa-solid fa-pen",
      style: :secondary,
    }
  end

  def channel_toggle_action(channel)
    return unless policy(channel).toggle?

    {
      label: (channel.enabled? ? "Disable" : "Enable"),
      url: toggle_admin_channel_path(channel),
      icon: (channel.enabled? ? "fa-solid fa-toggle-on" : "fa-solid fa-toggle-off"),
      style: :secondary,
      method: :patch,
    }
  end

  def channel_regenerate_token_action(channel, credential)
    return unless credential && policy(channel).regenerate_token?

    {
      label: "Regenerate Token",
      url: regenerate_token_admin_channel_path(channel),
      icon: "fa-solid fa-rotate",
      style: :secondary,
      method: :post,
      data: { turbo_confirm: "Regenerate this channel token? The current token will stop working." },
    }
  end

  def channel_delete_action(channel)
    return unless policy(channel).destroy?

    {
      label: "Delete",
      url: admin_channel_path(channel),
      icon: "fa-solid fa-trash",
      style: :danger_outline,
      method: :delete,
      data: {
        controller: "confirm",
        confirm_title_value: "Delete Channel",
        confirm_message_value: "Are you sure you want to delete this channel? This action cannot be undone.",
      },
    }
  end
end
