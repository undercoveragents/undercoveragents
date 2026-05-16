# frozen_string_literal: true

class ChatsController < ApplicationController
  include ChatUiSupport

  layout "chat"

  before_action :authorize_preview_client, if: :admin_client_preview?
  before_action :set_agent_and_version
  before_action :set_chat, only: [:show, :destroy, :cancel]
  before_action :set_sidebar_chats, only: [:index, :show]

  def index
    return redirect_to(admin_client_preview_page_path(client: current_client_record)) if admin_client_preview?

    redirect_to_most_recent_or_new if @agent

    # No published pipeline/agent available — show welcome
  end

  def show
    if admin_client_preview? && !request.format.turbo_stream?
      return redirect_to(admin_client_preview_page_path(client: current_client_record, chat: @chat))
    end

    render_chat_surface(chat: @chat, component: build_chat_component(variant: :client))
  end

  def create
    @chat = build_chat
    @chat.save!
    redirect_to(chat_redirect_path(@chat))
  end

  def destroy
    @chat.destroy!
    redirect_to chat_collection_redirect_path, status: :see_other
  end

  def cancel
    @chat.stop_stream!
    render_chat_status(chat: @chat)
  end

  def more
    set_sidebar_chats
    respond_to do |format|
      format.turbo_stream
    end
  end

  private

  def authorize_preview_client
    authorize current_client_record, :show?
  end

  def set_agent_and_version
    @agent = current_client_record&.client_agent
  end

  def set_chat
    @chat = scoped_chats.find(params.expect(:id))
    @agent = @chat.agent
  end

  def set_sidebar_chats
    @pagy_chats, @chats = pagy(:countless, scoped_chats.recent, limit: 20)
  end

  def scoped_chats
    user_chats_for_channel(channel: current_client_record)
  end

  def build_chat
    build_user_chat(agent: @agent, channel: current_client_record)
  end

  def redirect_to_most_recent_or_new
    most_recent = scoped_chats.recent.first
    if most_recent
      redirect_to chat_redirect_path(most_recent)
    else
      @chat = build_chat
      @chat.save!
      redirect_to chat_redirect_path(@chat)
    end
  end

  def chat_redirect_path(chat)
    return admin_client_preview_page_path(client: current_client_record, chat:) if admin_client_preview?

    chat_path(chat)
  end

  def chat_collection_redirect_path
    return admin_client_preview_page_path(client: current_client_record) if admin_client_preview?

    chats_path
  end
end
