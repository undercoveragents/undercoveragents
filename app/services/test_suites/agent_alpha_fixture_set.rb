# frozen_string_literal: true

require "digest"

module TestSuites
  class AgentAlphaFixtureSet
    include AgentAlphaFixtureCleanup
    include AgentAlphaFixtureContext
    include AgentAlphaFixtureFlowData
    include AgentAlphaFixtureTestSuite

    attr_reader :agent, :api_channel, :client_channel, :mission, :operation, :render_context,
                :skill, :skill_catalog, :test_case, :test_suite, :tool, :user

    def self.build!(**attributes)
      new(**attributes).tap(&:build!)
    end

    def initialize(**attributes)
      @tenant = attributes.fetch(:tenant)
      @user = attributes.fetch(:user)
      @test_case = attributes.fetch(:test_case)
      @model_id = attributes.fetch(:model_id)
      @llm_connector = attributes[:llm_connector]
      @model_record = attributes[:model_record]
      @token = attributes.fetch(:token)
      @render_context = build_render_context
    end

    def build!
      @operation = @tenant.operations.create!(
        name: render_context.fetch(:benchmark_operation_name),
        description: "Scenario fixtures for #{scenario_key}",
      )
      @mission = build_mission!
      @agent = build_agent!
      @tool = build_tool!
      @skill_catalog = build_skill_catalog!
      @skill = build_skill!
      @client_channel = build_client_channel!
      @api_channel = build_api_channel!
      @test_suite = build_test_suite!
      seed_agent_chat!
      self
    end

    def cleanup!
      cleanup_fixture_records!
    end

    private

    def scenario_key
      test_case.scenario_key.presence || "test-case-#{test_case.id}"
    end

    def build_mission!
      operation.missions.create!(
        name: render_context.fetch(:benchmark_mission_name),
        description: "Fixture mission for #{scenario_key}",
        flow_data: benchmark_flow_data,
      )
    end

    def build_agent!
      Agent.new(
        operation:,
        name: render_context.fetch(:benchmark_agent_name),
        description: "Fixture agent for #{scenario_key}",
        instructions: "Answer support questions concisely and ask for missing details only when needed.",
        agent_type: "general",
      ).tap do |record|
        record.model_id = @model_id
        record.llm_connector = @llm_connector if @llm_connector.present?
        record.temperature = 0.2
        record.enabled = true
        record.save!
      end
    end

    def build_tool!
      Tool.new(
        operation:,
        name: render_context.fetch(:benchmark_tool_name),
        description: "Fixture mission tool for #{scenario_key}",
        tool_type: "mission_tool",
      ).tap do |record|
        record.configurator = Tools::MissionTool.new(
          mission_id: mission.id,
          instructions: "Use this mission when the caller needs a concise ticket summary.",
        )
        record.save!
      end
    end

    def build_skill_catalog!
      operation.skill_catalogs.create!(
        name: render_context.fetch(:benchmark_skill_catalog_name),
        description: "Fixture catalog for #{scenario_key}",
      )
    end

    def build_skill!
      skill_catalog.skills.create!(
        name: render_context.fetch(:benchmark_skill_name),
        description: "Refund policy fixture for #{scenario_key}",
        instructions: "Use this skill when the user asks about refunds, billing reviews, or duplicate charges.",
      )
    end

    def build_client_channel!
      Channel.create!(
        tenant: @tenant,
        name: render_context.fetch(:benchmark_channel_name),
        description: "Fixture client channel for #{scenario_key}",
        channel_type: "client",
        configuration: {
          "title" => "Support Desk",
          "welcome_message" => "<p>Welcome to the support desk.</p>",
          "footer" => "<p>Answers may be AI-generated.</p>",
        },
      ).tap do |channel|
        ChannelTarget.create!(channel:, target: agent, default: true, position: 0)
      end
    end

    def build_api_channel!
      Channel.create!(
        tenant: @tenant,
        name: render_context.fetch(:benchmark_api_channel_name),
        description: "Fixture API channel for #{scenario_key}",
        channel_type: "api",
        configuration: {
          "response_mode" => "sync",
          "access_scope" => "all",
        },
      ).tap do |channel|
        ChannelTarget.create!(channel:, target: agent, default: true, position: 0)
      end
    end

    def seed_agent_chat!
      return unless user

      chat = Chat.create!(
        agent:,
        user:,
        model: @model_record,
        title: "#{agent.name} Fixture Chat",
        execution_context: :application,
      )
      chat.messages.create!(role: :user, content: "How do refunds work?", model: @model_record)
      chat.messages.create!(
        role: :assistant,
        content: "Share the charge details and support can review the refund request.",
        model: @model_record,
      )
    end

    def channel_for_test_case
      return api_channel if ["channel-05", "channel-06", "channel-08"].include?(scenario_key)

      client_channel
    end
  end
end
