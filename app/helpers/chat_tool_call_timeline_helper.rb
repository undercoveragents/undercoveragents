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
    annotate_assistant_turn_actions!(entries)
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

    grouped_entry.merge(kind: :tool_group_message, source_message: message)
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
      entries.last[:source_message] = grouped_entry[:source_message] if grouped_entry[:source_message].present?
    else
      entries << grouped_entry
    end
  end

  def annotate_assistant_turn_actions!(entries)
    assistant_turn_entries = []

    Array(entries).each do |entry|
      if user_render_entry?(entry)
        assign_assistant_turn_actions!(assistant_turn_entries)
        assistant_turn_entries = []
        next
      end

      assistant_turn_entries << entry if assistant_render_entry?(entry)
    end

    assign_assistant_turn_actions!(assistant_turn_entries)
    entries
  end

  def assign_assistant_turn_actions!(entries)
    return if entries.empty?

    last_entry = entries.last
    action_message = assistant_action_message(last_entry)
    return if action_message.blank?

    last_entry[:action_message] = action_message
    last_entry[:action_copy_text] = assistant_turn_copy_text(entries)
  end

  def assistant_render_entry?(entry)
    return true if entry&.dig(:kind) == :tool_group_message

    entry&.dig(:kind) == :message && entry[:message]&.assistant?
  end

  def user_render_entry?(entry)
    entry&.dig(:kind) == :message && entry[:message]&.user?
  end

  def assistant_action_message(entry)
    return entry[:source_message] if entry&.dig(:kind) == :tool_group_message
    return unless entry&.dig(:kind) == :message

    entry[:message] if entry[:message]&.assistant?
  end

  def assistant_turn_copy_text(entries)
    Array(entries).filter_map { |entry| assistant_entry_copy_text(entry) }.join("\n\n").presence.to_s
  end

  def assistant_entry_copy_text(entry)
    case entry&.dig(:kind)
    when :tool_group_message
      tool_group_entry_copy_text(entry)
    when :message
      assistant_message_copy_text(entry[:message])
    end
  end

  def assistant_message_copy_text(message)
    return unless message&.assistant?

    parts = []
    content = message.display_content.to_s.strip
    parts << content if content.present?

    tool_calls_text = tool_call_entries_copy_text(
      grouped_tool_call_render_entries(Array(message.tool_calls), message:),
    )
    parts << tool_calls_text if tool_calls_text.present?
    parts.join("\n").presence
  end

  def tool_call_entries_copy_text(entries)
    Array(entries).filter_map { |entry| tool_group_entry_copy_text(entry) }.join("\n").presence
  end

  def tool_group_entry_copy_text(entry)
    lines = []
    group_title = entry[:group_title].to_s.strip
    lines << group_title if group_title.present?

    Array(entry[:items]).each do |item|
      line = tool_group_item_copy_text(item)
      lines << line if line.present?
    end

    lines.join("\n").presence
  end

  def tool_group_item_copy_text(item)
    label = item[:label].to_s.strip
    phrase = item[:phrase].to_s.strip
    return if label.blank? && phrase.blank?
    return "- #{label}" if phrase.blank?
    return "- #{phrase}" if label.blank?

    "- #{label}: #{phrase}"
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
