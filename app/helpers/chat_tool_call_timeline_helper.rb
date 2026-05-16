# frozen_string_literal: true

module ChatToolCallTimelineHelper
  def chat_message_render_entries(messages, chat: nil)
    messages = Array(messages)

    entries = messages.each_with_object([]) do |message, built_entries|
      grouped_entry = grouped_chat_message_render_entry(message, chat:)

      if grouped_entry
        append_grouped_chat_message_render_entry(built_entries, grouped_entry)
      else
        built_entries << { kind: :message, message: }
      end
    end

    keep_trailing_tool_group_running!(entries, messages, chat:)
  end

  def chat_tool_call_status(tool_call, chat: nil)
    running_chat_tool_call?(tool_call, chat:) ? :running : :complete
  end

  def chat_tool_call_state_label(status)
    status.to_s == "running" ? "In progress" : "Completed"
  end

  private

  def grouped_chat_message_render_entry(message, chat: nil)
    grouped_entry = grouped_render_entry_for_message(message, chat:)
    return unless grouped_entry

    grouped_entry.merge(kind: :tool_group_message)
  end

  def grouped_render_entry_for_message(message, chat: nil)
    return unless assistant_tool_only_message?(message)

    visible_tool_calls = visible_groupable_tool_calls(message, chat:)
    return if visible_tool_calls.empty?

    grouped_render_entry_for_tool_calls(visible_tool_calls, message:, chat:)
  end

  def assistant_tool_only_message?(message)
    message&.assistant? && message.content.blank?
  end

  def visible_groupable_tool_calls(message, chat: nil)
    visible_tool_calls = Array(message.tool_calls).select { |tool_call| chat_tool_call_badge_visible?(tool_call) }
    return [] if visible_tool_calls.empty?
    return [] if visible_tool_calls.any? { |tool_call| tool_call_has_custom_widget?(tool_call) }
    return [] unless grouped_tool_call_render_entry(visible_tool_calls, message:, chat:)

    visible_tool_calls
  end

  def grouped_render_entry_for_tool_calls(tool_calls, message: nil, chat: nil)
    render_entries = grouped_tool_call_render_entries(tool_calls, message:, chat:)
    return unless render_entries.one? && render_entries.first[:kind] == :group

    render_entries.first
  end

  def running_chat_tool_call?(tool_call, chat: nil)
    return false unless trackable_chat_tool_call?(tool_call)
    return false unless tool_call.duration_ms.nil?

    resolved_chat_for_tool_call(tool_call, chat:)&.status.to_s == "streaming"
  rescue StandardError
    false
  end

  def trackable_chat_tool_call?(tool_call)
    tool_call.present? && tool_call.respond_to?(:duration_ms)
  end

  def resolved_chat_for_tool_call(tool_call, chat: nil)
    chat || tool_call.message&.chat
  end

  def grouped_tool_call_render_entry(tool_calls, message: nil, chat: nil)
    return grouped_render_entry_for_tool_calls(tool_calls, message:) if chat.nil?

    grouped_render_entry_for_tool_calls(tool_calls, message:, chat:)
  end

  def grouped_tool_call_render_entries(tool_calls, message: nil, chat: nil)
    return chat_tool_call_render_entries(tool_calls, message:) if chat.nil?

    chat_tool_call_render_entries(tool_calls, message:, chat:)
  end

  def append_grouped_chat_message_render_entry(entries, grouped_entry)
    if entries.last&.dig(:kind) == :tool_group_message && entries.last[:group_title] == grouped_entry[:group_title]
      entries.last[:items].concat(grouped_entry[:items])
      entries.last[:status] = chat_tool_group_status(entries.last[:items])
    else
      entries << grouped_entry
    end
  end

  def keep_trailing_tool_group_running!(entries, messages, chat: nil)
    trailing_entry = entries.last
    trailing_chat = chat || messages.last&.chat

    return entries unless trailing_tool_group_streaming?(trailing_entry, trailing_chat)

    trailing_entry[:status] = :running
    entries
  end

  def trailing_tool_group_streaming?(entry, chat)
    entry&.dig(:kind) == :tool_group_message && chat&.status.to_s == "streaming"
  end

  def chat_tool_group_status(items)
    Array(items).any? { |item| item[:status].to_s == "running" } ? :running : :complete
  end

  def tool_call_has_custom_widget?(tool_call)
    normalized_chat_tool_call_widget_config(tool_call).present?
  rescue StandardError
    false
  end
end
