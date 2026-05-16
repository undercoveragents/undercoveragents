# frozen_string_literal: true

# Shared base for jobs that process a chat message and stream the response via
# the chat UI ActionCable stream. Subclasses implement +perform+ and call the helpers below.
#
# Responsibilities kept here:
#   - Configuring a chat from its agent (delegated to Chat#configure_for_agent)
#   - Attachment loading + content-type filtering
#   - Cancellation detection mid-stream
#   - Chat UI stream broadcasting (chunks, tool events, error messages)
#   - Post-response finalisation (status, capability dispatch, title fallback)
class BaseChatResponseJob < ApplicationJob
  queue_as :default

  # Discard if the chat has been deleted between enqueue and execution.
  discard_on ActiveRecord::RecordNotFound

  private

  # ---------------------------------------------------------------------------
  # Chat setup
  # ---------------------------------------------------------------------------

  # Attachments

  def load_attachments(signed_ids)
    return [] if signed_ids.blank?

    signed_ids.filter_map { |sid| ActiveStorage::Blob.find_signed(sid) }
              .select { |blob| supported_attachment?(blob) }
  end

  # Only pass attachment types that the Chat Completions API supports.
  # Images are universally supported via base64 image_url on vision models.
  def supported_attachment?(blob)
    blob.content_type.to_s.start_with?("image/")
  end

  # ---------------------------------------------------------------------------
  # Streaming helpers
  # ---------------------------------------------------------------------------

  def check_cancellation!(chat)
    return unless chat.is_a?(Chat)

    current_status = chat.class.where(id: chat.id).pick(:status)
    raise Chat::CancelledError if current_status == "cancelled"
  end

  def setup_tool_broadcasting(chat)
    chat.before_tool_call_execution do |tool_call|
      check_cancellation!(chat)
      chat.broadcast_status_update(phase: nil)
      broadcast_tool_event(chat, "start", streamed_tool_call_id(tool_call), tool_call.name)
    end

    chat.after_tool_call_execution do |tool_call_id, tool_name, _duration|
      check_cancellation!(chat)
      broadcast_tool_event(chat, "complete", tool_call_id, tool_name)
    end
  end

  def broadcast_chunk(chat, content, kind: :content)
    normalized_content = normalized_chunk_content(content)
    return if normalized_content.empty?

    broadcast_ui_chunk(chat, normalized_content, kind)
  end

  # Keep the current assistant text in memory so interrupted streams can still
  # persist one final message body without checkpointing every chunk to the DB.
  def append_stream_content(chat, content)
    normalized_content = normalized_chunk_content(content)
    return if normalized_content.empty?

    stream_content_state(chat) << normalized_content
  end

  def backfill_missing_stream_content(chat, response)
    missing_content = missing_stream_content(chat, response)
    return if missing_content.empty?

    chat.broadcast_status_update(phase: nil)
    append_stream_content(chat, missing_content)
    broadcast_chunk(chat, missing_content, kind: :content)
  end

  def persist_stream_content(chat)
    message_record = chat.instance_variable_get(:@message)
    return unless message_record&.persisted?

    content = stream_content_state(chat)
    return if content.empty?
    return if message_record.content.to_s == content

    message_record.update!(
      content:,
      updated_at: Time.current,
    )
  end

  def clear_stream_content(chat)
    @stream_content_states&.delete(stream_content_key(chat))
  end

  def broadcast_tool_event(chat, event, tool_call_id, tool_name)
    metadata = ToolCalls::DisplayMetadataResolver.resolve(tool_name, chat:)
    status = event == "start" ? :running : :complete
    event_data = { event:, tool_call_id:, tool_name:, metadata:, status: }

    broadcast_ui_tool_event(chat, event_data)
  end

  def broadcast_error_message(chat, error)
    return unless chat

    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "error",
        chat_id: chat.id,
        message: error.message,
      ),
    )
  end

  # ---------------------------------------------------------------------------
  # Finalisation
  # ---------------------------------------------------------------------------

  def finalize_chat(chat)
    return unless chat

    if cancelled_chat?(chat)
      chat.broadcast_status_update
      return
    end

    chat.idle!
    chat.broadcast_status_update

    handled = Capabilities::EventDispatcher.dispatch(:chat_response_completed, chat:)
    generate_simple_title(chat) unless handled
  ensure
    clear_stream_content(chat) if chat
  end

  def generate_simple_title(chat)
    return if chat.title.present? && chat.title != Chat::DEFAULT_TITLE

    first_message = chat.messages.where(role: :user).order(:created_at).first
    return unless first_message

    chat.update!(title: first_message.display_content.truncate(60))
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

  def stream_content_state(chat)
    @stream_content_states ||= {}
    @stream_content_states[stream_content_key(chat)] ||= +""
  end

  def stream_content_key(chat)
    chat_id = chat.respond_to?(:id) ? chat.id : nil
    chat_id || chat.object_id
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

  def streamed_tool_call_id(tool_call)
    tool_call&.try(:tool_call_id).presence || tool_call&.id
  end

  def missing_stream_content(chat, response)
    final_content = normalized_chunk_content(response.respond_to?(:content) ? response.content : response)
    return "" if final_content.empty?

    streamed_content = stream_content_state(chat)
    return "" if streamed_content == final_content
    return final_content if streamed_content.empty?
    return final_content.delete_prefix(streamed_content) if final_content.start_with?(streamed_content)

    ""
  end

  def broadcast_ui_chunk(chat, content, kind)
    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "chunk",
        chat_id: chat.id,
        content:,
        kind: kind.to_s,
      ),
    )
  end

  def broadcast_ui_tool_event(chat, event_data)
    metadata = event_data[:metadata]

    ActionCable.server.broadcast(
      chat.ui_stream_channel_name,
      chat.ui_stream_payload(
        type: "tool_event",
        chat_id: chat.id,
        event: event_data[:event],
        tool_call_id: event_data[:tool_call_id],
        tool_name: event_data[:tool_name],
        display_name: metadata.display_name,
        icon: metadata.icon,
        widget_payload: metadata.widget_payload(
          status: event_data[:status],
          phrase: metadata.sample_phrase(status: event_data[:status]),
        ),
      ),
    )
  end

  def cancelled_chat?(chat)
    return chat.cancelled? unless chat.is_a?(Chat)

    chat.class.where(id: chat.id).pick(:status) == "cancelled"
  end
end
