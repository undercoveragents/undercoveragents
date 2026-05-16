# frozen_string_literal: true

module ChatToolCallHelper
  include ChatToolCallTimelineHelper
  include ChatToolCallRowHelper

  def chat_visible_messages(chat)
    return [] unless chat

    request.env["chat.visible_messages"] ||= {}
    request.env["chat.visible_messages"][chat.id] ||= Chats::VisibleMessageLoader.load(chat)
  end

  def chat_tool_call_display_name(tool_call)
    chat_tool_call_presentation(tool_call).display_name
  end

  def chat_tool_call_icon(tool_call)
    chat_tool_call_presentation(tool_call).icon
  end

  def chat_tool_call_duration_label(tool_call)
    duration_ms = tool_call&.duration_ms.to_i
    return if duration_ms <= 0

    if duration_ms >= 60_000
      minutes = duration_ms / 60_000
      seconds = (duration_ms % 60_000) / 1000.0
      "#{minutes}m #{format("%.1f", seconds)}s"
    elsif duration_ms >= 1_000
      "#{format("%.2f", duration_ms / 1000.0)}s"
    else
      "#{duration_ms}ms"
    end
  end

  def chat_tool_call_widget_data(tool_call, status: :complete, phrase: nil, chat: nil)
    presentation = resolved_chat_tool_call_presentation(tool_call, chat:)
    phrase ||= presentation.sample_phrase(status:)

    presentation.widget_payload(status:, phrase:).merge(controller: "tool-widget")
  end

  def chat_tool_call_render_entries(tool_calls, status: nil, message: nil, chat: nil)
    child_chat_map = child_chat_map_for_message(message, chat:)

    Array(tool_calls).each_with_object([]) do |tool_call, entries|
      append_chat_tool_call_render_entry(
        entries,
        build_chat_tool_call_render_item(
          tool_call,
          status:,
          child_chat: child_chat_map[Chats::SubagentBranchResolver.tool_call_identity(tool_call)],
          chat:,
        ),
      )
    end
  end

  def chat_tool_call_badge_visible?(tool_call)
    return false if tool_call.blank?
    return true unless tool_call.respond_to?(:tool_call_badge_visible?)

    tool_call.tool_call_badge_visible?
  rescue StandardError => e
    Rails.logger.error "[ChatToolCallHelper] tool call badge visibility failed: #{e.message}"
    true
  end

  def chat_tool_call_presentation(tool_call, chat: nil)
    presentation = merged_chat_tool_call_presentation(tool_call, chat:)
    apply_chat_tool_call_presentation_override(tool_call, presentation)
  end

  def render_chat_tool_call_widget(tool_call)
    config = normalized_chat_tool_call_widget_config(tool_call)
    return if config.blank?

    render_chat_tool_call_widget_partial(config)
  rescue StandardError => e
    Rails.logger.error "[ChatToolCallHelper] tool call widget render failed: #{e.message}"
    nil
  end

  private

  def merged_chat_tool_call_presentation(tool_call, chat: nil)
    return ToolCalls::DisplayMetadataResolver.resolve(nil) if tool_call.blank?

    resolved_metadata = ToolCalls::DisplayMetadataResolver.resolve(tool_call.name,
                                                                   chat: chat || tool_call.message&.chat,)
    resolved_metadata.with(
      display_name: tool_call.display_name.presence || resolved_metadata.display_name,
      icon: tool_call.icon.presence || resolved_metadata.icon,
    )
  end

  def apply_chat_tool_call_presentation_override(tool_call, presentation)
    return presentation unless tool_call.respond_to?(:tool_call_presentation_override)

    tool_call.tool_call_presentation_override(presentation) || presentation
  rescue StandardError => e
    Rails.logger.error "[ChatToolCallHelper] tool call presentation override failed: #{e.message}"
    presentation
  end

  def normalized_chat_tool_call_widget_config(tool_call)
    return unless tool_call.respond_to?(:tool_call_widget_render_config)

    config = tool_call.tool_call_widget_render_config
    return if config.blank?

    partial = config[:partial].to_s.presence
    return if partial.blank?

    {
      partial:,
      locals: config.fetch(:locals, {}).merge(tool_call:),
      view_path: config[:view_path].to_s.presence,
    }
  end

  def render_chat_tool_call_widget_partial(config)
    return render(partial: config[:partial], locals: config[:locals]) if config[:view_path].blank?

    render_plugin_partial(view_path: config[:view_path], partial: config[:partial], locals: config[:locals])
  end

  def build_chat_tool_call_render_item(tool_call, status:, child_chat: nil, chat: nil)
    status ||= chat_tool_call_status(tool_call, chat:)
    presentation = resolved_chat_tool_call_presentation(tool_call, chat:)
    phrase = presentation.sample_phrase(status:)

    {
      tool_call:,
      presentation:,
      status:,
      label: presentation.display_name,
      icon_class: presentation.icon,
      phrase:,
      duration_label: chat_tool_call_duration_label(tool_call),
      widget_data: chat_tool_call_widget_data(tool_call, status:, phrase:, chat:),
      child_chat:,
    }
  end

  def append_chat_tool_call_render_entry(entries, item)
    append_grouped_chat_tool_call_render_entry(entries, item, item[:presentation].group_title.to_s)
  end

  def append_grouped_chat_tool_call_render_entry(entries, item, group_title)
    if entries.last&.dig(:kind) == :group && entries.last[:group_title] == group_title
      entries.last[:items] << item
      entries.last[:status] = chat_tool_group_status(entries.last[:items])
    else
      entries << { kind: :group, group_title:, status: item[:status], items: [item] }
    end
  end

  def child_chat_map_for_message(message, chat: nil)
    resolved_chat = chat || message&.chat
    return {} unless message&.assistant? && resolved_chat.present?

    chat_subagent_child_chat_assignments(resolved_chat)[message.id] || {}
  end

  def resolved_chat_tool_call_presentation(tool_call, chat: nil)
    return chat_tool_call_presentation(tool_call) if chat.nil?

    chat_tool_call_presentation(tool_call, chat:)
  end

  def chat_subagent_child_chat_assignments(chat)
    request.env["chat_tool_call_helper.child_chat_assignments"] ||= {}
    request.env["chat_tool_call_helper.child_chat_assignments"][chat.id] ||=
      Chats::SubagentBranchResolver.child_chat_assignments_for(chat, messages: chat_visible_messages(chat))
  end
end
