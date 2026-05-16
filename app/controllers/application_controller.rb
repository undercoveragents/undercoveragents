# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication
  before_action :set_current_request_context

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def pundit_user
    current_user
  end

  private

  # ── Authentication ─────────────────────────────────────────────────────────────
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = (User.active.find_by(id: session[:user_id]) if session[:user_id])
    Current.user = @current_user
    @current_user
  end
  helper_method :current_user

  def current_tenant
    return @current_tenant if defined?(@current_tenant)

    @current_tenant = resolve_current_tenant
    Current.tenant = @current_tenant
    @current_tenant
  end
  helper_method :current_tenant

  # ── Client Settings ───────────────────────────────────────────────────────────
  def current_client
    @current_client ||= current_client_record&.settings_payload ||
                        Channel.current_client_settings(tenant: current_tenant)
  end
  helper_method :current_client

  def current_client_record
    return @current_client_record if defined?(@current_client_record)

    @current_client_record = chat_preview_channel_record || Channel.current_client_channel(tenant: current_tenant)
  end
  helper_method :current_client_record

  def chat_preview_channel_record
    return @chat_preview_channel_record if defined?(@chat_preview_channel_record)

    @chat_preview_channel_record = if chat_preview_request?
                                     scoped_channels.by_type("client").includes(channel_targets: :target)
                                                    .friendly.find(chat_preview_channel_identifier)
                                   end
  end
  helper_method :chat_preview_channel_record

  def admin_client_preview?
    chat_preview_channel_record.present?
  end
  helper_method :admin_client_preview?

  # ── Current Operation ───────────────────────────────────────────────────────
  def current_operation
    return @current_operation if defined?(@current_operation)

    @current_operation = resolve_current_operation
    session[:current_operation_id] = @current_operation.id if @current_operation
    Current.operation = @current_operation
    @current_operation
  end
  helper_method :current_operation

  # ── Sidebar State ───────────────────────────────────────────────────────────
  def sidebar_collapsed?
    session[:sidebar_collapsed] == true
  end
  helper_method :sidebar_collapsed?

  # ── Operation Scoping ──────────────────────────────────────────────────────
  def scoped_agents
    current_operation ? Agent.where(operation: current_operation) : Agent.none
  end
  helper_method :scoped_agents

  def scoped_missions
    current_operation ? Mission.where(operation: current_operation) : Mission.none
  end
  helper_method :scoped_missions

  def scoped_tools
    current_operation ? Tool.where(operation: current_operation) : Tool.none
  end
  helper_method :scoped_tools

  def scoped_skill_catalogs
    current_operation ? SkillCatalog.where(operation: current_operation) : SkillCatalog.none
  end
  helper_method :scoped_skill_catalogs

  def scoped_rag_flows
    current_operation ? RagFlow.where(operation: current_operation) : RagFlow.none
  end
  helper_method :scoped_rag_flows

  def scoped_operations
    current_tenant ? current_tenant.operations : Operation.none
  end
  helper_method :scoped_operations

  def scoped_connectors
    current_tenant ? current_tenant.connectors : Connector.none
  end
  helper_method :scoped_connectors

  def scoped_channels
    current_tenant ? current_tenant.channels : Channel.none
  end
  helper_method :scoped_channels

  def scoped_clients
    current_tenant ? current_tenant.clients : Client.none
  end
  helper_method :scoped_clients

  def scoped_api_clients
    current_tenant ? current_tenant.api_clients : ApiClient.none
  end
  helper_method :scoped_api_clients

  def tenant_scoped_test_suites
    return TestSuite.none unless current_tenant

    TestSuite.where(agent_id: current_tenant.agents.select(:id))
             .or(TestSuite.where(mission_id: current_tenant.missions.select(:id)))
  end
  helper_method :tenant_scoped_test_suites

  def tenant_scoped_mission_runs
    return MissionRun.none unless current_tenant

    MissionRun.where(mission_id: current_tenant.missions.select(:id))
  end
  helper_method :tenant_scoped_mission_runs

  def tenant_scoped_chats
    return Chat.none unless current_tenant

    base_scope = Chat.where(user_id: current_tenant.users.select(:id))
                     .or(Chat.where(agent_id: current_tenant.agents.select(:id)))
                     .or(Chat.where(mission_id: current_tenant.missions.select(:id)))

    base_scope.or(Chat.where(parent_chat_id: base_scope.select(:id)))
  end
  helper_method :tenant_scoped_chats

  def user_chats_for_channel(channel:)
    base_scope = Chat.user.for_user(current_user)
    return base_scope.none unless channel

    base_scope.for_channel(channel)
  end

  def current_system_preference
    @current_system_preference ||= SystemPreference.current(tenant: current_tenant)
  end
  helper_method :current_system_preference

  def chat_preview_request?
    current_user.admin? && chat_preview_channel_identifier.present?
  end

  def chat_preview_channel_identifier
    params[:preview_channel_id].presence || preview_channel_id_from_admin_show
  end

  def preview_channel_id_from_admin_show
    return unless controller_path == "admin/channels" && action_name == "show" && params[:view] == "preview"

    params[:id]
  end

  def agent_alpha_display_name
    "Agent Alpha"
  end
  helper_method :agent_alpha_display_name

  def agent_alpha_icon
    "fa-solid fa-brain"
  end
  helper_method :agent_alpha_icon

  def agent_alpha_panel_title
    return "Unavailable" unless agent_alpha_configured?

    current_agent_alpha_chat_for_header&.display_title_for_ui || Chat::DEFAULT_TITLE
  end
  helper_method :agent_alpha_panel_title

  def agent_alpha_configured?
    current_tenant.present? && SystemPreference.llm_configured?(tenant: current_tenant)
  end
  helper_method :agent_alpha_configured?

  def current_agent_alpha_chat_for_header
    return unless current_user && current_tenant

    agent = Agent.find_builtin_by_key("agent_alpha", tenant: current_tenant)
    return unless agent

    chats = current_user.chats.where(agent:, execution_context: :application)
    if session[:admin_agent_alpha_chat_id].present?
      remembered_chat = chats.find_by(id: session[:admin_agent_alpha_chat_id])
    end
    remembered_chat || chats.order(updated_at: :desc).first
  end
  helper_method :current_agent_alpha_chat_for_header

  def require_authentication
    return if current_user

    session[:return_to] = request.fullpath unless request.xhr?
    redirect_to new_session_path
  end

  def bootstrap_session_for(user)
    tenant = user.tenant
    tenant.ensure_core_resources!

    session[:user_id] = user.id
    session[:current_operation_id] = tenant.default_operation&.id
  end

  def default_path_after_sign_in(user)
    user.admin? ? admin_root_path : root_path
  end

  def user_not_authorized
    redirect_back_or_to(root_path, alert: t("shared.not_authorized"))
  end

  def set_current_request_context
    Current.user = current_user if current_user
    Current.tenant = current_tenant if current_user
    Current.operation = current_operation if current_user && request.path.start_with?("/admin")
  end

  def resolve_current_tenant
    current_user&.tenant
  end

  def resolve_current_operation
    return unless current_tenant

    current_tenant.ensure_core_resources!
    selected_current_operation || current_tenant.default_operation
  end

  def selected_current_operation
    return unless session[:current_operation_id]

    current_tenant.operations.find_by(id: session[:current_operation_id])
  end
end
