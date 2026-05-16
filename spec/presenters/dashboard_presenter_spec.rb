# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardPresenter do
  describe "#initialize" do
    it "loads global metrics when no operation is given" do
      presenter = described_class.new
      expect(presenter.chats_count).to eq(0)
      expect(presenter.agents_count).to be >= 0
    end
  end

  describe "operation filtering" do
    let(:op_a) { create(:operation, name: "Alpha Ops") }
    let(:op_b) { create(:operation, name: "Beta Ops") }
    let(:agent_a) { create(:agent, name: "Alpha Agent", operation: op_a) }
    let(:agent_b) { create(:agent, name: "Beta Agent", operation: op_b) }

    before do
      create(:tool, :sql_query, operation: op_a)
      create(:tool, :sql_query, operation: op_b)
      create(:mission, operation: op_a)
      create(:chat, agent: agent_a)
      create(:chat, agent: agent_b)
    end

    it "scopes agents to the given operation" do
      presenter = described_class.new(operation: op_a)
      expect(presenter.agents_count).to eq(1)
    end

    it "scopes tools to the given operation" do
      presenter = described_class.new(operation: op_a)
      expect(presenter.tools_count).to eq(1)
    end

    it "scopes missions to the given operation" do
      presenter = described_class.new(operation: op_a)
      expect(presenter.missions_count).to eq(1)
    end

    it "scopes chats through agents" do
      presenter = described_class.new(operation: op_a)
      expect(presenter.chats_count).to eq(1)
    end

    it "returns all counts when no operation is given" do
      presenter = described_class.new
      expect(presenter.agents_count).to be >= 2
      expect(presenter.chats_count).to be >= 2
    end

    it "stores the operation" do
      presenter = described_class.new(operation: op_a)
      expect(presenter.operation).to eq(op_a)
    end
  end

  describe "tenant aggregate scoping" do
    let(:tenant) { create(:tenant, name: "Tenant Alpha") }
    let(:other_tenant) { create(:tenant, name: "Tenant Beta") }

    # rubocop:disable Metrics/MethodLength
    def build_tenant_activity(tenant:, other_tenant:)
      tenant_operation = create(:operation, tenant:, name: "Tenant Ops")
      other_operation = create(:operation, tenant: other_tenant, name: "Foreign Ops")
      tenant_agent = create(
        :agent,
        operation: tenant_operation,
        name: "Tenant Agent",
        llm_connector: create(:connector, :llm_provider, :enabled, tenant:),
      )
      other_agent = create(
        :agent,
        operation: other_operation,
        name: "Foreign Agent",
        llm_connector: create(:connector, :llm_provider, :enabled, tenant: other_tenant),
      )
      tenant_mission = create(:mission, operation: tenant_operation, name: "Tenant Mission")
      other_mission = create(:mission, operation: other_operation, name: "Foreign Mission")
      tenant_chat = create(:chat, agent: tenant_agent)
      other_chat = create(:chat, agent: other_agent)
      tenant_message = create(:message, chat: tenant_chat, input_tokens: 15, output_tokens: 25)
      other_message = create(:message, chat: other_chat, input_tokens: 40, output_tokens: 60)
      create(:tool_call, message: tenant_message)
      create(:tool_call, message: other_message)
      tenant_run = create(:mission_run, mission: tenant_mission, status: "running")
      create(:mission_run, mission: other_mission, status: "running")
      tenant_suite = create(:test_suite, agent: tenant_agent)
      other_suite = create(:test_suite, agent: other_agent)
      tenant_suite_run = create(:test_suite_run, test_suite: tenant_suite, status: "completed")
      create(:test_suite_run, test_suite: other_suite, status: "completed")

      {
        tenant_run:,
        tenant_suite_run:,
      }
    end
    # rubocop:enable Metrics/MethodLength

    it "scopes tenant aggregate counts and tokens" do
      build_tenant_activity(tenant:, other_tenant:)

      presenter = described_class.new(tenant:)

      aggregate_failures do
        expect(presenter.chats_count).to eq(1)
        expect(presenter.messages_count).to eq(1)
        expect(presenter.total_tool_calls).to eq(1)
        expect(presenter.input_tokens).to eq(15)
        expect(presenter.output_tokens).to eq(25)
        expect(presenter.mission_runs_count).to eq(1)
        expect(presenter.test_runs_count).to eq(1)
      end
    end

    it "scopes recent tenant mission runs" do
      data = build_tenant_activity(tenant:, other_tenant:)

      presenter = described_class.new(tenant:)

      expect(presenter.recent_mission_runs.map(&:id)).to contain_exactly(data[:tenant_run].id)
    end

    it "scopes recent tenant test runs" do
      data = build_tenant_activity(tenant:, other_tenant:)

      presenter = described_class.new(tenant:)

      expect(presenter.recent_test_runs.map(&:id)).to contain_exactly(data[:tenant_suite_run].id)
    end
  end

  describe "getting started" do
    it "keeps the first agent step pending when only builtin agents exist" do
      create(:system_preference, :configured)

      builtin_agent = create(
        :agent,
        builtin: true,
        builtin_key: "mission_designer",
        selectable: false,
      )
      chat = create(:chat, agent: builtin_agent)
      create(:message, chat:)

      presenter = described_class.new
      agent_step = presenter.getting_started_steps.find { |step| step[:title] == "Build Your First Agent" }

      expect(agent_step[:done]).to be(false)
      expect(presenter.show_getting_started).to be(true)
    end

    it "marks the Agent Alpha step complete after an application chat has a message" do
      create(:system_preference, :configured)

      agent_alpha = create(
        :agent,
        builtin: true,
        builtin_key: "agent_alpha",
        selectable: false,
      )
      chat = create(:chat, agent: agent_alpha, execution_context: :application)
      create(:message, chat:)

      presenter = described_class.new
      agent_alpha_step = presenter.getting_started_steps.find do |step|
        step[:title] == "Ask Agent Alpha Anything"
      end

      expect(agent_alpha_step[:done]).to be(true)
    end
  end
end
