# frozen_string_literal: true

module ChatUiSupport
  extend ActiveSupport::Concern

  include ChatUiHelper

  private

  def build_user_chat(agent:, channel:)
    # Long-running workers or tests can temporarily poison Chat column metadata.
    # Refresh once so channel-backed chat creation still persists the channel FK.
    Chat.reset_column_information if channel.present? && !Chat.columns_hash.key?("channel_id")

    Chat.new(
      agent:,
      channel:,
      channel_target: channel&.default_target,
      title: Chat::DEFAULT_TITLE,
      model: find_user_chat_model(agent),
      user: current_user,
      execution_context: :user,
    )
  end

  def find_user_chat_model(agent)
    model_id = agent&.resolved_model_id
    return Model.first if model_id.blank?

    Model.find_by(model_id:) || Model.first
  end

  def render_chat_surface(chat:, component:)
    @messages = load_chat_messages(chat)
    model_record = chat_model_for_attachments(chat)
    base_component = component.with_thinking_level_options(thinking_level_options_for_chat(chat))
    @chat_component = base_component.with_attachment_model(model_record)
    @chat_component = @chat_component.with_thinking_level_selector_visible(
      @chat_component.thinking_level_selector_visible? &&
      chat_thinking_level_selector_supported?(chat, model_record:),
    )

    return unless turbo_stream_chat_refresh_request?

    return render_chat_status(chat:) if streaming_status_only_refresh?(chat:)

    render_chat_refresh(chat:, messages: @messages, component: @chat_component)
  end

  def enqueue_chat_message(chat:, content:, runtime_context: {}, attachment_signed_ids: nil)
    signed_ids = attachment_signed_ids.nil? ? upload_chat_attachments(chat) : Array(attachment_signed_ids)
    chat.enqueue_response!(content:, attachment_signed_ids: signed_ids, runtime_context:)

    render_chat_status(chat:)
  end

  def persist_message_feedback(chat:, message:, user:, attributes:)
    feedback = message.message_feedbacks.find_or_initialize_by(user:)
    feedback.chat = chat
    feedback.assign_attributes(attributes)
    feedback
  end

  def render_chat_refresh(chat:, messages:, component:)
    render turbo_stream: [
      turbo_stream.update(
        "chat-#{chat.id}-messages",
        partial: "shared/chat/messages_content",
        locals: { messages:, component:, chat: },
      ),
      turbo_stream.replace(
        "chat-#{chat.id}-status",
        partial: "shared/chat/status",
        locals: { chat: },
      ),
    ]
  end

  def render_chat_status(chat:)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "chat-#{chat.id}-status",
          partial: "shared/chat/status",
          locals: { chat: },
        )
      end
      format.any { head :ok }
    end
  end

  def turbo_stream_chat_refresh_request?
    request.format.turbo_stream? && params[:format] == "turbo_stream"
  end

  def streaming_status_only_refresh?(chat:)
    chat.streaming?
  end

  def load_chat_messages(chat)
    messages = Chats::VisibleMessageLoader.load(chat, include_attachments: true)
    cache_chat_visible_messages(chat, messages)
    messages
  end

  def cache_chat_visible_messages(chat, messages)
    request.env["chat.visible_messages"] ||= {}
    request.env["chat.visible_messages"][chat.id] = messages
  end

  def upload_chat_attachments(chat)
    files = params.dig(:message, :attachments)
    return [] if files.blank?

    model_record = chat_model_for_attachments(chat)

    Array(files).filter_map do |file|
      next unless model_record&.supports_attachment_content_type?(file.content_type)

      blob = ActiveStorage::Blob.create_and_upload!(
        io: file,
        filename: file.original_filename,
        content_type: file.content_type,
      )
      blob.signed_id
    end
  end

  def chat_model_for_attachments(chat)
    model_id = chat.agent&.resolved_model_id
    return chat.model if model_id.blank?

    Model.find_by(model_id:) || chat.model
  end
end
