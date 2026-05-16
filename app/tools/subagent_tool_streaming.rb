# frozen_string_literal: true

module SubagentToolStreaming
  private

  def stream_nested_subagent_response(question)
    check_nested_cancellation!
    chat = build_nested_subagent_chat(question)
    check_nested_cancellation!(chat)
    response, streamed_content = ask_nested_subagent_question(chat, question)

    finish_nested_subagent_chat(chat, response, streamed_content)
  rescue StandardError => e
    handle_nested_subagent_stream_error(chat, e)
    raise
  end

  def stream_nested_subagent_response?
    @parent_chat.is_a?(Chat)
  end

  def build_nested_subagent_chat(question)
    chat = @agent.build_chat(**ask_options_for(question))
    setup_tool_broadcasting(chat)
    chat.streaming!
    chat.broadcast_status_update
    chat
  end

  def ask_nested_subagent_question(chat, question)
    check_nested_cancellation!(chat)
    stream_phase = nil
    streamed_content = +""
    response = chat.ask(question) do |chunk|
      stream_phase = stream_nested_subagent_chunk(chat, chunk, stream_phase, streamed_content)
    end

    check_nested_cancellation!(chat)

    [response, streamed_content]
  end

  def stream_nested_subagent_chunk(chat, chunk, stream_phase, streamed_content)
    check_nested_cancellation!(chat)
    next_phase = advance_stream_phase(chat, stream_phase, chunk)
    broadcast_chunk(chat, chunk.thinking, kind: :thinking) if chunk.respond_to?(:thinking)
    return next_phase if chunk.content.nil?

    normalized_content = normalized_chunk_content(chunk.content)
    streamed_content << normalized_content unless normalized_content.empty?
    broadcast_chunk(chat, chunk.content, kind: :content)
    next_phase
  end

  def finish_nested_subagent_chat(chat, response, streamed_content)
    backfill_missing_stream_content(chat, response, streamed_content)
    chat.idle!
    chat.broadcast_status_update

    decorate_nested_subagent_response(
      chat,
      nested_subagent_response_content(chat, response, streamed_content),
    )
  end

  def nested_subagent_response_content(chat, response, streamed_content)
    final_content = response_content(response)
    return final_content if final_content.present?

    fallback_content = latest_meaningful_child_message_content(chat)
    return fallback_content if fallback_content.present?

    streamed_content.to_s
  end

  def latest_meaningful_child_message_content(chat)
    messages = chat.messages
    recent_messages = if messages.respond_to?(:where)
                        messages.where(role: SubagentTool::TOOL_MESSAGE_ROLES).order(:created_at, :id)
                      else
                        in_memory_tool_messages(messages)
                      end

    Array(recent_messages).reverse_each.lazy
                          .map { |message| message.content.to_s.presence }
                          .find(&:present?)
  end

  def in_memory_tool_messages(messages)
    Array(messages).select do |message|
      SubagentTool::TOOL_MESSAGE_ROLES.include?(message.respond_to?(:role) ? message.role.to_s : nil)
    end
  end

  def handle_nested_subagent_stream_error(chat, error)
    if error.is_a?(Chat::CancelledError)
      chat&.stop_stream!
      return
    end

    chat&.idle!
    chat&.broadcast_status_update
    broadcast_error_message(chat, error) if chat
  end

  def setup_tool_broadcasting(chat)
    chat.before_tool_call_execution do |tool_call|
      check_nested_cancellation!(chat)
      chat.broadcast_status_update(phase: nil)
      broadcast_tool_event(chat, "start", streamed_tool_call_id(tool_call), tool_call.name)
    end

    chat.after_tool_call_execution do |tool_call_id, tool_name, _duration|
      check_nested_cancellation!(chat)
      broadcast_tool_event(chat, "complete", tool_call_id, tool_name)
    end
  end

  def check_nested_cancellation!(chat = nil)
    parent_chat_id = @parent_chat.id if @parent_chat.respond_to?(:id)
    child_chat_id = chat.id if chat.respond_to?(:id)
    chat_ids = [parent_chat_id, child_chat_id].compact
    return if chat_ids.empty?
    return unless Chat.exists?(id: chat_ids, status: :cancelled)

    raise Chat::CancelledError
  end

  def streamed_tool_call_id(tool_call)
    tool_call&.try(:tool_call_id).presence || tool_call&.id
  end

  def advance_stream_phase(chat, current_phase, chunk)
    next_phase = stream_phase_for(chunk)
    return current_phase if next_phase == current_phase

    chat.broadcast_status_update(phase: next_phase)
    next_phase
  end

  def stream_phase_for(chunk)
    return nil if chunk.respond_to?(:tool_call?) && chunk.tool_call?
    return nil if chunk.respond_to?(:content) && chunk.content.present?
    return :thinking if chunk.respond_to?(:thinking) && !chunk.thinking.nil?

    nil
  end

  def broadcast_chunk(chat, content, kind: :content)
    normalized_content = normalized_chunk_content(content)
    return if normalized_content.empty?

    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "chunk",
        chat_id: chat.id,
        content: normalized_content,
        kind: kind.to_s,
      ),
    )
  end

  def broadcast_tool_event(chat, event, tool_call_id, tool_name)
    metadata = ToolCalls::DisplayMetadataResolver.resolve(tool_name, chat:)
    status = event == "start" ? :running : :complete

    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "tool_event",
        chat_id: chat.id,
        event:,
        tool_call_id:,
        tool_name:,
        display_name: metadata.display_name,
        icon: metadata.icon,
        widget_payload: metadata.widget_payload(
          status:,
          phrase: metadata.sample_phrase(status:),
        ),
      ),
    )
  end

  def broadcast_error_message(chat, error)
    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "error",
        chat_id: chat.id,
        message: error.message,
      ),
    )
  end

  def normalized_chunk_content(content)
    return "" if content.nil?
    return content.text.to_s if content.respond_to?(:text)

    if content.is_a?(Hash)
      return content[:text].to_s if content.key?(:text)
      return content["text"].to_s if content.key?("text")
    end

    content.to_s
  end

  def backfill_missing_stream_content(chat, response, streamed_content)
    final_content = normalized_chunk_content(response.respond_to?(:content) ? response.content : response)
    return if final_content.empty?
    return if streamed_content == final_content

    missing_content = missing_stream_content(final_content, streamed_content)
    return if missing_content.empty?

    chat.broadcast_status_update(phase: nil)
    broadcast_chunk(chat, missing_content, kind: :content)
  end

  def missing_stream_content(final_content, streamed_content)
    return final_content if streamed_content.empty?
    return final_content.delete_prefix(streamed_content) if final_content.start_with?(streamed_content)

    ""
  end
end
