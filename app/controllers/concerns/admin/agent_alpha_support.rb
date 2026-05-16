# frozen_string_literal: true

module Admin
  module AgentAlphaSupport
    SESSION_CHAT_ID_KEY = :admin_agent_alpha_chat_id
    REFERENCE_KINDS = [
      "missions", "tools", "skill_catalogs", "skills", "agents", "clients", "connectors",
      "rag_flows", "test_suites",
    ].freeze

    private

    def agent_alpha_record
      @agent_alpha_record ||= BuiltinAgents::Resolver.find!("agent_alpha", tenant: current_tenant)
    end

    def agent_alpha_chats
      current_user.chats.where(
        agent: agent_alpha_record,
        execution_context: :application,
      ).order(updated_at: :desc)
    end

    def agent_alpha_chat
      @agent_alpha_chat ||= find_or_create_agent_alpha_chat
    end

    def find_or_create_agent_alpha_chat
      remember_agent_alpha_chat(resolved_agent_alpha_chat || create_agent_alpha_chat)
    end

    def create_agent_alpha_chat
      Chat.create!(
        agent: agent_alpha_record,
        execution_context: :application,
        model: resolved_agent_alpha_model,
        title: agent_alpha_chat_title,
        user: current_user,
      )
    end

    def agent_alpha_chat_title
      "#{agent_alpha_display_name} — #{Time.current.strftime("%b %d, %H:%M")}"
    end

    def resolved_agent_alpha_model
      Model.find_by(model_id: agent_alpha_record.resolved_model_id)
    end

    def remember_agent_alpha_chat(chat)
      session[SESSION_CHAT_ID_KEY] = chat.id
      chat
    end

    def remembered_agent_alpha_chat
      chat_id = session[SESSION_CHAT_ID_KEY]
      return if chat_id.blank?

      agent_alpha_chats.find_by(id: chat_id).tap do |chat|
        session.delete(SESSION_CHAT_ID_KEY) if chat.blank?
      end
    end

    def requested_agent_alpha_chat
      agent_alpha_chats.find_by(id: params[:chat_id])
    end

    def resolved_agent_alpha_chat
      return if params[:new].present?
      return requested_or_fallback_agent_alpha_chat if params[:chat_id].present?

      remembered_or_latest_agent_alpha_chat
    end

    def requested_or_fallback_agent_alpha_chat
      requested_agent_alpha_chat || remembered_or_latest_agent_alpha_chat
    end

    def remembered_or_latest_agent_alpha_chat
      remembered_agent_alpha_chat || latest_agent_alpha_chat
    end

    def latest_agent_alpha_chat
      agent_alpha_chats.first
    end

    def agent_alpha_reference_kinds
      REFERENCE_KINDS
    end
  end
end
