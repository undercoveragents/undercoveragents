# frozen_string_literal: true

# Extracts all query and presentation logic from DashboardController
# into a testable, cacheable presenter.
class DashboardPresenter
  include Rails.application.routes.url_helpers

  # -- Hero metrics --
  attr_reader :total_tokens, :input_tokens, :output_tokens,
              :chats_count, :messages_count, :total_tool_calls

  # -- Platform inventory --
  attr_reader :connectors_count, :active_connectors, :agents_count, :enabled_agents,
              :skill_catalogs_count, :skills_count,
              :tools_count, :enabled_tools, :missions_count, :mission_runs_count,
              :active_mission_runs, :rag_flows_count, :enabled_rag_flows,
              :test_suites_count, :test_runs_count,
              :users_count, :channels_count, :plugins_count, :enabled_plugins

  # -- Charts --
  attr_reader :chats_by_day, :messages_by_day, :tokens_by_day, :tool_calls_by_day

  # -- Activity --
  attr_reader :recent_chats, :recent_mission_runs, :recent_test_runs

  # -- Getting started --
  attr_reader :show_getting_started, :getting_started_steps

  # -- Operation filter --
  attr_reader :operation
  attr_reader :tenant

  def initialize(tenant: Current.tenant || Tenant.default_tenant, operation: nil)
    @tenant = tenant
    @operation = operation
    load_hero_metrics
    load_platform_inventory
    load_charts_data
    load_recent_activity
    load_getting_started
  end

  private

  # ── Scoped base queries ────────────────────────────────────────────────────

  def agents_scope
    operation ? Agent.where(operation:) : tenant.agents
  end

  def tools_scope
    operation ? Tool.where(operation:) : tenant.tools
  end

  def skill_catalogs_scope
    operation ? SkillCatalog.where(operation:) : tenant.skill_catalogs
  end

  def skills_scope
    unless operation
      return Skill.joins(:skill_catalog).where(
        skill_catalogs: { operation_id: tenant.operations.select(:id) },
      )
    end

    Skill.joins(:skill_catalog).where(skill_catalogs: { operation_id: operation.id })
  end

  def missions_scope
    operation ? Mission.where(operation:) : tenant.missions
  end

  def rag_flows_scope
    operation ? RagFlow.where(operation:) : tenant.rag_flows
  end

  def chats_scope
    return Chat.where(agent_id: agents_scope.select(:id)) if operation

    Chat.where(user_id: tenant.users.select(:id))
        .or(Chat.where(agent_id: tenant.agents.select(:id)))
        .or(Chat.where(mission_id: tenant.missions.select(:id)))
  end

  def messages_scope
    Message.where(chat_id: chats_scope.select(:id))
  end

  def tool_calls_scope
    ToolCall.where(message_id: messages_scope.select(:id))
  end

  def mission_runs_scope
    MissionRun.where(mission_id: missions_scope.select(:id))
  end

  def test_suites_scope
    if operation
      TestSuite.where(agent_id: agents_scope.select(:id))
               .or(TestSuite.where(mission_id: missions_scope.select(:id)))
    else
      TestSuite.where(agent_id: tenant.agents.select(:id))
               .or(TestSuite.where(mission_id: tenant.missions.select(:id)))
    end
  end

  def test_runs_scope
    TestSuiteRun.where(test_suite_id: test_suites_scope.select(:id))
  end

  # ── Loaders ────────────────────────────────────────────────────────────────

  def load_hero_metrics
    @input_tokens  = messages_scope.sum(Message.total_input_activity_sum).to_i
    @output_tokens = messages_scope.sum(:output_tokens).to_i
    @total_tokens  = @input_tokens + @output_tokens
    @chats_count   = chats_scope.count
    @messages_count = messages_scope.count
    @total_tool_calls = tool_calls_scope.count
  end

  def load_platform_inventory
    load_build_inventory
    load_data_inventory
    load_settings_inventory
  end

  def load_build_inventory
    @connectors_count  = tenant.connectors.count
    @active_connectors = tenant.connectors.enabled.count
    @agents_count      = agents_scope.count
    @enabled_agents    = agents_scope.enabled.count
    @skill_catalogs_count = skill_catalogs_scope.count
    @skills_count = skills_scope.count
    @tools_count       = tools_scope.count
    @enabled_tools     = tools_scope.enabled.count
  end

  def load_data_inventory
    @missions_count      = missions_scope.count
    @mission_runs_count  = mission_runs_scope.count
    @active_mission_runs = mission_runs_scope.active.count
    @rag_flows_count     = rag_flows_scope.count
    @enabled_rag_flows   = rag_flows_scope.enabled.count
    @test_suites_count   = test_suites_scope.count
    @test_runs_count     = test_runs_scope.count
  end

  def load_settings_inventory
    @users_count     = tenant.users.count
    @channels_count  = operation ? operation.channels.count : tenant.channels.count
    @plugins_count   = UndercoverAgents::PluginSystem.registry.count
    @enabled_plugins = UndercoverAgents::PluginSystem.registry.enabled.count
  end

  def load_charts_data
    load_time_series_charts
  end

  def load_time_series_charts
    @chats_by_day = chats_scope.where(created_at: 30.days.ago..)
                               .group_by_day(:created_at, last: 30)
                               .count

    @messages_by_day = messages_scope.where(created_at: 30.days.ago..)
                                     .group_by_day(:created_at, last: 30)
                                     .count

    @tokens_by_day = token_usage_by_day

    @tool_calls_by_day = tool_calls_scope.where(created_at: 30.days.ago..)
                                         .group_by_day(:created_at, last: 30)
                                         .count
  end

  def load_recent_activity
    @recent_chats = chats_scope.order(updated_at: :desc).limit(5).to_a
    @recent_mission_runs = mission_runs_scope.order(created_at: :desc).limit(5).to_a
    @recent_test_runs = test_runs_scope.order(created_at: :desc).limit(5).to_a

    preload_records(@recent_chats, :agent)
    preload_records(@recent_mission_runs, :mission)
  end

  def load_getting_started
    @show_getting_started = !tenant.connectors.llm_providers.exists? || !any_model_configured? ||
                            !user_created_agents_scope.exists? ||
                            !chats_scope.playground.joins(:messages).exists? ||
                            !agent_alpha_chat_started?
    @getting_started_steps = build_getting_started_steps
  end

  def build_getting_started_steps
    [
      { done: tenant.connectors.llm_providers.exists?, icon: "fa-solid fa-brain",
        title: "Connect an LLM Provider",
        description: "Add your first LLM connection (OpenAI, Anthropic, etc.) to power your agents.",
        link_text: "Add Connector", link_path: new_admin_connector_path(type: "llm_provider"), },
      { done: any_model_configured?, icon: "fa-solid fa-sliders",
        title: "Set Default Models",
        description: "Configure at least one default model (LLM, embedding, or image) in Preferences.",
        link_text: "Open Preferences", link_path: admin_preferences_path, },
      { done: user_created_agents_scope.exists?, icon: "fa-solid fa-user-secret",
        title: "Build Your First Agent",
        description: "Create an agent with instructions, a model, and tools to handle queries.",
        link_text: "View Agents", link_path: admin_agents_path, },
      { done: chats_scope.playground.joins(:messages).exists?, icon: "fa-solid fa-comments",
        title: "Test in the Playground",
        description: "Start a conversation with your agent in the Playground to see it in action.",
        link_text: "Open Playground", link_path: admin_playground_chats_path, },
      agent_alpha_getting_started_step,
    ]
  end

  def agent_alpha_getting_started_step
    {
      done: agent_alpha_chat_started?,
      icon: "fa-solid fa-lightbulb",
      title: "Ask Agent Alpha Anything",
      description: "Open Agent Alpha from the sidebar and ask a question about the app, " \
                   "your data, or what to do next.",
      link_text: "Open Agent Alpha",
      action: "click->dashboard#openAgentAlpha",
    }
  end

  def any_model_configured?
    pref = tenant.system_preference
    return false unless pref

    (pref.llm_connector_id.present? && pref.model_id.present?) ||
      (pref.embedding_connector_id.present? && pref.embedding_model_id.present?) ||
      (pref.image_connector_id.present? && pref.image_model_id.present?)
  end

  def agent_alpha_chat_started?
    agent_alpha = Agent.find_builtin_by_key("agent_alpha", tenant:)
    return false unless agent_alpha

    agent_alpha.chats.application.joins(:messages).exists?
  end

  def user_created_agents_scope
    agents_scope.user_created
  end

  def token_usage_by_day
    input = messages_scope.where(created_at: 30.days.ago..)
                          .group_by_day(:created_at, last: 30)
                          .sum(Message.total_input_activity_sum)
                          .transform_values(&:to_i)

    output = messages_scope.where(created_at: 30.days.ago..)
                           .group_by_day(:created_at, last: 30)
                           .sum(:output_tokens)
                           .transform_values(&:to_i)

    [
      { name: "Input Tokens", data: input },
      { name: "Output Tokens", data: output },
    ]
  end

  def preload_records(records, associations)
    ActiveRecord::Associations::Preloader.new(
      records:,
      associations:,
    ).call
  end
end
