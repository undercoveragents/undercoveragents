# frozen_string_literal: true

module Admin
  module Playground
    class ChatsController < BaseController
      include ChatUiSupport
      include PlaygroundAccess

      layout "admin"

      before_action :set_agents, only: [:index, :show]
      before_action :set_chat, only: [:show, :destroy, :cancel]
      before_action :ensure_chat_accessible!, only: [:show]
      before_action :set_agent_from_params, only: [:more]

      def index
        @agent = find_requested_agent
        return if handled_redirect_without_agent?

        redirect_to_existing_or_new_chat
      end

      def show
        @agent = @chat.agent
        @pagy_chats, @chats = pagy(:countless, scoped_chats.recent, limit: 20)
        render_chat_surface(
          chat: @chat,
          component: build_chat_component(variant: :playground, agent_name: @agent.name),
        )
      end

      def create
        @agent = find_playground_agent!(params[:agent_id])
        @chat = build_playground_chat(@agent)
        @chat.save!
        redirect_to admin_playground_chat_path(@chat)
      end

      def destroy
        @chat.destroy!
        redirect_to admin_playground_chats_path
      end

      def cancel
        @chat.stop_stream!
        render_chat_status(chat: @chat)
      end

      def more
        @pagy_chats, @chats = pagy(:countless, scoped_chats.recent, limit: 20)
        respond_to do |format|
          format.turbo_stream
        end
      end

      private

      def set_agents
        @agents = playground_available_agents
      end

      def set_chat
        @chat = current_user.chats.find(params.expect(:id))
      end

      def set_agent_from_params
        @agent = find_requested_agent
      end

      def scoped_chats
        base = Chat.playground.for_user(current_user)
        return base.for_agent(@agent) if @agent

        base.where(agent_id: playground_available_agent_ids)
      end

      def build_playground_chat(agent)
        model_record = find_model_for(agent)
        Chat.new(
          agent:,
          title: Chat::DEFAULT_TITLE,
          model: model_record,
          user: current_user,
        )
      end

      def find_model_for(agent)
        Model.find_by(model_id: agent.resolved_model_id) || Model.first!
      end

      def create_new_chat_and_redirect
        @chat = build_playground_chat(@agent)
        @chat.save!
        redirect_to admin_playground_chat_path(@chat)
      end

      def find_requested_agent
        find_playground_agent!(params[:agent_id])
      end

      # Handles redirects and agent selection when no agent was resolved from params.
      # Returns true if a redirect was performed (caller should halt), false otherwise.
      def handled_redirect_without_agent?
        return false if @agent

        most_recent = scoped_chats.recent.first
        if most_recent
          redirect_to admin_playground_chat_path(most_recent)
          return true
        end

        false
      end

      def redirect_to_existing_or_new_chat
        return unless @agent

        most_recent = scoped_chats.recent.first
        if most_recent
          redirect_to admin_playground_chat_path(most_recent)
        else
          create_new_chat_and_redirect
        end
      end

      def ensure_chat_accessible!
        return if playground_chat_accessible?(@chat)

        if request.format.turbo_stream?
          head :not_found
        else
          redirect_to admin_playground_chats_path, alert: playground_unavailable_alert
        end
      end
    end
  end
end
