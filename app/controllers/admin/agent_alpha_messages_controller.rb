# frozen_string_literal: true

module Admin
  class AgentAlphaMessagesController < BaseController
    include ChatUiSupport
    include AgentAlphaSupport

    layout false

    def create
      return head :unprocessable_content unless agent_alpha_configured?

      enqueue_chat_message(
        chat: agent_alpha_chat,
        content: agent_alpha_message_content,
        runtime_context: agent_alpha_runtime_context,
      )
    end

    def feedback
      feedback = persist_message_feedback(
        chat: agent_alpha_chat,
        message: agent_alpha_message,
        user: current_user,
        attributes: feedback_params.to_h,
      )

      if feedback.save
        head :no_content
      else
        render json: { errors: feedback.errors.full_messages }, status: :unprocessable_content
      end
    end

    private

    def agent_alpha_chat
      @agent_alpha_chat ||= if params[:message].present?
                              agent_alpha_chats.find(message_params[:chat_id])
                            else
                              agent_alpha_message.chat
                            end
    end

    def agent_alpha_message
      @agent_alpha_message ||= Message.joins(:chat).merge(agent_alpha_chats).visible.find(params.expect(:message_id))
    end

    def message_params
      params.expect(message: [:content, :chat_id, :ui_context_token, :references, :thinking_effort])
    end

    def feedback_params
      params.expect(feedback: [:value, :category, :comment])
    end

    def agent_alpha_message_content
      ChatReferences::MessagePayload.pack(
        content: message_params[:content],
        references: agent_alpha_references,
      )
    end

    def agent_alpha_runtime_context
      ui_context = AgentAlpha::PageContext.verify(
        message_params[:ui_context_token],
        user: current_user,
        tenant: current_tenant,
      )
      ui_context = ui_context_with_references(ui_context)

      runtime_context = AgentAlpha::RuntimeContext.build(ui_context:, tenant: current_tenant)
      return runtime_context unless agent_alpha_thinking_level_selector_visible?

      runtime_context.dup.tap do |context|
        llm_config = context.fetch(:llm_config, {}).dup
        llm_config[:thinking_effort] = normalized_message_thinking_effort
        context[:llm_config] = llm_config
      end
    end

    def ui_context_with_references(ui_context)
      return ui_context if agent_alpha_references.blank?

      (ui_context || {}).deep_dup.tap do |context|
        context["references"] = agent_alpha_references
        context["reference_trigger"] ||= AgentAlpha::PageContext::DEFAULT_REFERENCE_TRIGGER
      end
    end

    def agent_alpha_references
      @agent_alpha_references ||= ChatReferences::SelectionResolver.new(
        tenant: current_tenant,
        operation: current_operation,
        kinds: agent_alpha_reference_kinds,
      ).resolve(message_params[:references])
    end

    def agent_alpha_thinking_level_selector_visible?
      chat_model_for_attachments(agent_alpha_chat).try(:supports_reasoning?) != false
    end

    def normalized_message_thinking_effort
      effort = message_params[:thinking_effort].to_s.presence
      return effort if Llm::ChatOptions::THINKING_EFFORTS.include?(effort)

      nil
    end
  end
end
