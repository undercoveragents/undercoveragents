# frozen_string_literal: true

# Processes chat responses for the app's Turbo-streamed chat surfaces.
# Delivery is shared across user, playground, and mission-designer chats;
# only the runtime setup differs by chat context.
class ChatResponseJob < BaseChatResponseJob
  # @param chat_id [Integer] The chat ID
  # @param content [String] The user message content
  # @param attachment_signed_ids [Array<String>] Signed IDs of uploaded ActiveStorage blobs
  def perform(chat_id, content, attachment_signed_ids = [], runtime_context = {}, tenant_id: nil)
    chat = find_chat(chat_id, tenant_id:)

    prepare_chat!(chat, runtime_context: runtime_context.to_h)
    stream_response(chat, content, attachment_signed_ids)
  rescue Chat::CancelledError
    persist_stream_content(chat) if chat
    nil
  rescue StandardError => e
    persist_stream_content(chat) if chat
    Rails.logger.error "[ChatResponseJob] Error: #{e.message}"
    broadcast_error_message(chat, e)
  ensure
    finalize_chat(chat)
  end

  private

  def find_chat(chat_id, tenant_id: nil)
    return Chat.find(chat_id) if tenant_id.blank?

    tenant_scoped_chats(tenant_id).find(chat_id)
  end

  def tenant_scoped_chats(tenant_id)
    user_chats = Chat.where(user_id: User.where(tenant_id:).select(:id))
    agent_chats = Chat.where(agent_id: Agent.joins(:operation).where(operations: { tenant_id: }).select(:id))
    mission_chats = Chat.where(
      mission_id: Mission.joins(:operation).where(operations: { tenant_id: }).select(:id),
    )
    base_scope = user_chats.or(agent_chats).or(mission_chats)

    base_scope.or(Chat.where(parent_chat_id: base_scope.select(:id)))
  end

  def prepare_chat!(chat, runtime_context: {})
    check_cancellation!(chat)
    clear_stream_content(chat)
    configure_chat!(chat, runtime_context:)
    setup_tool_broadcasting(chat)
    chat.streaming!
    chat.broadcast_status_update
  end

  def configure_chat!(chat, runtime_context: {})
    case chat.response_context
    when :user, :channel, :application
      configure_agent_chat!(chat, runtime_context:)
    when :playground
      configure_agent_chat!(chat, require_playground_support: true)
    when :mission_designer
      configure_mission_designer_chat!(chat)
    else
      raise unsupported_context_error(chat)
    end
  end

  def configure_agent_chat!(chat, require_playground_support: false, runtime_context: {})
    agent = chat.agent

    raise "No agent is configured for this chat." unless agent

    if require_playground_support && !chat.playground_agent_supported?
      raise "Playground does not support agents with built-in tools."
    end

    chat.configure_for_agent(agent, runtime_context:)
  end

  def configure_mission_designer_chat!(chat)
    mission = chat.mission

    raise "Mission designer chat is missing its mission." unless mission

    BuiltinAgents::Runner.configure_chat!(
      chat:,
      builtin_key: "mission_designer",
      input_values: {
        mission_name: mission.name,
        mission_description: mission.description.to_s,
      },
      runtime_context: { mission: },
    )
  end

  def stream_response(chat, content, attachment_signed_ids)
    message_payload = ChatReferences::MessagePayload.parse(content)
    stream_phase = nil
    initial_message_id = chat.messages.maximum(:id).to_i

    response = chat.ask(message_payload.prompt_content, **ask_options_for(attachment_signed_ids)) do |chunk|
      check_cancellation!(chat)
      stream_phase = advance_stream_phase(chat, stream_phase, chunk)
      broadcast_chunk(chat, chunk.thinking, kind: :thinking) if chunk.respond_to?(:thinking)

      unless chunk.content.nil?
        append_stream_content(chat, chunk.content)
        broadcast_chunk(chat, chunk.content, kind: :content)
      end
    end

    check_cancellation!(chat)

    backfill_missing_stream_content(chat,
                                    strip_synthetic_terminal_response(chat, response,
                                                                      since_message_id: initial_message_id,),)
  ensure
    persist_user_message_payload(chat, message_payload, since_message_id: initial_message_id)
  end

  def persist_user_message_payload(chat, message_payload, since_message_id:)
    return unless message_payload.references?

    user_message = chat.messages.user.where("id > ?", since_message_id).order(:id).first
    return unless user_message

    user_message.update!(content: message_payload.packed_content)
  end

  def ask_options_for(attachment_signed_ids)
    attachments = load_attachments(attachment_signed_ids)
    attachments.any? ? { with: attachments } : {}
  end

  def strip_synthetic_terminal_response(chat, response, since_message_id:)
    final_content = terminal_response_content(response)
    return response if final_content.blank?

    synthetic_message = synthetic_terminal_message(chat, final_content, since_message_id:)
    return response unless synthetic_message

    synthetic_message.destroy!
    ""
  end

  def terminal_response_content(response)
    content = response.respond_to?(:content) ? response.content : response
    normalized_chunk_content(content)
  end

  def synthetic_terminal_message(chat, final_content, since_message_id:)
    recent_messages = recent_stream_messages(chat, since_message_id:)
    return unless synthetic_terminal_response?(recent_messages, final_content)

    recent_messages.last
  end

  def recent_stream_messages(chat, since_message_id:)
    chat.messages.where("id > ?", since_message_id).order(:created_at, :id).to_a
  end

  def synthetic_terminal_response?(recent_messages, final_content)
    assistant_messages = recent_messages.select(&:assistant?)
    return false unless synthetic_terminal_context?(recent_messages, assistant_messages)

    final_message = assistant_messages.last
    prior_content = assistant_messages[0...-1].sum("") { |message| message.content.to_s }

    synthetic_terminal_match?(recent_messages.last, final_message, final_content, prior_content)
  end

  def synthetic_terminal_context?(recent_messages, assistant_messages)
    assistant_messages.size >= 2 && recent_messages.any?(&:tool?)
  end

  def synthetic_terminal_match?(last_message, final_message, final_content, prior_content)
    prior_content.present? &&
      final_message == last_message &&
      final_message.content.to_s == final_content &&
      final_content == prior_content
  end

  def unsupported_context_error(chat)
    "Unsupported chat context '#{chat.execution_context}' for response dispatch."
  end
end
