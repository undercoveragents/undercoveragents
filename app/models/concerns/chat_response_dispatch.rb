# frozen_string_literal: true

module ChatResponseDispatch
  extend ActiveSupport::Concern

  def stop_stream!
    normalize_interrupted_tool_call_history!

    chats_to_cancel = [self] + streaming_descendant_chats
    cancelled_at = Time.current

    chats_to_cancel.each do |chat_record|
      chat_record.update!(status: "cancelled", updated_at: cancelled_at)
      chat_record.broadcast_status_update
    end
  end

  def response_context
    return :mission_designer if system? && mission_id.present?
    return :playground if playground?
    return :application if application?
    return :channel if channel?
    return :user if user?

    nil
  end

  def enqueue_response!(content:, attachment_signed_ids: [], runtime_context: {})
    raise unsupported_response_context_message unless response_context

    normalize_interrupted_tool_call_history!
    check_cost_limits!
    streaming_transition = start_response_stream
    broadcast_status_update

    ChatResponseJob.perform_later(
      *response_job_args(content:, attachment_signed_ids:, runtime_context:),
      tenant_id: response_job_tenant_id,
    )
  rescue StandardError
    recover_from_enqueue_failure(streaming_transition)
    raise
  end

  def configure_for_agent(agent, **)
    agent.configure_chat(self, user:, **)
  end

  private

  def normalize_interrupted_tool_call_history!
    tool_result_ids = normalized_tool_result_ids

    messages.where(role: :assistant).includes(:tool_calls).find_each do |message|
      dangling_tool_calls = dangling_tool_calls_for(message, tool_result_ids)
      dangling_tool_calls.each(&:destroy!) if dangling_tool_calls.any?

      destroy_blank_interrupted_assistant_message!(message)
    end
  end

  def normalized_tool_result_ids
    messages.where(role: :tool)
            .where.not(tool_call_id: nil)
            .reorder(nil)
            .distinct
            .pluck(:tool_call_id)
  end

  def dangling_tool_calls_for(message, tool_result_ids)
    message.tool_calls.reject do |tool_call|
      tool_result_ids.include?(tool_call.id) || persistent_widget_tool_call?(tool_call)
    end
  end

  def destroy_blank_interrupted_assistant_message!(message)
    message.reload
    return unless message.tool_calls.empty?
    return if message.content.present?
    return if message.thinking_text.present?

    message.destroy!
  end

  def persistent_widget_tool_call?(tool_call)
    return false unless tool_call.respond_to?(:tool_call_widget_render_config)

    tool_call.tool_call_widget_render_config.present?
  rescue StandardError
    false
  end

  def start_response_stream
    return :already_streaming if streaming?

    streaming!
    :started
  end

  def response_job_args(content:, attachment_signed_ids:, runtime_context: {})
    job_args = [id, content, Array(attachment_signed_ids)]
    job_args << runtime_context.deep_stringify_keys if runtime_context.present?
    job_args
  end

  def response_job_tenant_id
    tenant_id_for_chat(self) || tenant_id_for_chat(parent_chat)
  end

  def tenant_id_for_chat(chat_record)
    return if chat_record.blank?

    chat_record.user&.tenant_id ||
      tenant_id_for_operation_owner(chat_record.agent) ||
      tenant_id_for_operation_owner(chat_record.mission)
  end

  def tenant_id_for_operation_owner(record)
    record&.operation&.tenant_id
  end

  def recover_from_enqueue_failure(streaming_transition)
    return unless [true, :started].include?(streaming_transition)

    update!(status: "idle", updated_at: Time.current)
    broadcast_status_update
  end

  def unsupported_response_context_message
    "Unsupported chat context '#{execution_context}' for response dispatch."
  end

  def streaming_descendant_chats
    self.class.where(id: descendant_chat_ids, status: :streaming).to_a
  end

  def descendant_chat_ids
    descendant_ids = []
    frontier = [id]

    while frontier.any?
      frontier = self.class.where(parent_chat_id: frontier).pluck(:id)
      descendant_ids.concat(frontier)
    end

    descendant_ids
  end
end
