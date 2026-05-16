# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::AgentAlphaFixtureSet do
  let(:tenant) { create(:tenant) }
  let(:user) { create(:user, tenant:) }
  let(:source_operation) { create(:operation, tenant:) }
  let(:source_agent) { create(:agent, operation: source_operation) }
  let(:source_suite) { create(:test_suite, agent: source_agent) }
  let(:model_record) { create(:model, model_id: "gpt-4.1", name: "GPT 4.1") }
  let(:test_case) do
    create(:test_case, test_suite: source_suite, scenario_key: "cleanup-01", category: "agent")
  end

  describe "#cleanup!" do
    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it "removes every fixture operation record while preserving run chat evidence" do
      fixture = described_class.build!(
        tenant:,
        user:,
        test_case:,
        model_id: model_record.model_id,
        model_record:,
        token: "cleanup-token",
      )
      operation_id = fixture.operation.id
      built_test_suite_id = fixture.test_suite.id
      extra_agent = create(:agent, operation: fixture.operation)
      extra_mission = create(:mission, operation: fixture.operation)
      extra_skill_catalog = create(:skill_catalog, operation: fixture.operation)
      extra_rag_flow = create(:rag_flow, operation: fixture.operation)
      extra_suite = create(:test_suite, agent: extra_agent)
      extra_channel = create(:channel, :client, tenant:, name: "Unprefixed Fixture Channel")
      extra_channel_target = create(:channel_target, channel: extra_channel, target: extra_agent)
      preserved_chat = create(
        :chat,
        :test_context,
        agent: fixture.agent,
        mission: extra_mission,
        channel: extra_channel,
        channel_target: extra_channel_target,
      )
      preserved_result = create(:test_case_result, :passed, chat: preserved_chat)

      fixture.cleanup!

      expect(Operation.exists?(operation_id)).to be(false)
      expect(Agent.where(operation_id:)).to be_empty
      expect(Mission.where(operation_id:)).to be_empty
      expect(Tool.where(operation_id:)).to be_empty
      expect(SkillCatalog.where(operation_id:)).to be_empty
      expect(RagFlow.where(operation_id:)).to be_empty
      expect(TestSuite.where(id: [built_test_suite_id, extra_suite.id])).to be_empty
      expect(Channel.exists?(extra_channel.id)).to be(false)
      expect(preserved_result.reload.chat).to eq(preserved_chat)
      expect(preserved_chat.reload).to have_attributes(
        agent_id: nil,
        mission_id: nil,
        channel_id: nil,
        channel_target_id: nil,
      )
      expect(SkillCatalog.exists?(extra_skill_catalog.id)).to be(false)
      expect(RagFlow.exists?(extra_rag_flow.id)).to be(false)
    end

    it "ignores nil records during cleanup helpers" do
      fixture = described_class.allocate

      expect { fixture.send(:destroy_record, nil) }.not_to raise_error
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
  end

  describe "runtime context helpers" do
    let(:built_fixtures) { [] }
    let(:fixture) do
      described_class.build!(
        tenant:,
        user:,
        test_case:,
        model_id: model_record.model_id,
        model_record:,
        token: "runtime-token",
      ).tap { |record| built_fixtures << record }
    end

    after do
      built_fixtures.each { |record| record.cleanup! if record.operation&.persisted? }
    end

    it "reports empty context before records are built" do
      unbuilt_fixture = described_class.new(
        tenant:,
        user:,
        test_case:,
        model_id: model_record.model_id,
        model_record:,
        token: "unbuilt-token",
      )

      expect(unbuilt_fixture.report_context).to eq({})
    end

    it "reports built records for debug snapshots" do
      expect(fixture.report_context).to include(
        operation_id: fixture.operation.id,
        mission_id: fixture.mission.id,
        agent_id: fixture.agent.id,
        tool_id: fixture.tool.id,
        skill_catalog_id: fixture.skill_catalog.id,
        skill_id: fixture.skill.id,
        test_suite_id: fixture.test_suite.id,
      )
    end

    it "can build fixtures with an explicit LLM connector and no chat-seeding user" do
      connector = create(:connector, :llm_provider, tenant:)
      connector_fixture = described_class.build!(
        tenant:,
        user: nil,
        test_case:,
        model_id: model_record.model_id,
        model_record:,
        llm_connector: connector,
        token: "connector-token",
      )
      built_fixtures << connector_fixture

      expect(connector_fixture.agent.llm_connector).to eq(connector)
    end

    # rubocop:disable RSpec/MultipleExpectations
    it "selects runtime context by test case category" do
      expect(runtime_context_for(fixture, category: "mission")).to include(mission: fixture.mission)
      expect(runtime_context_for(fixture, category: "agent")).to include(current_agent: fixture.agent)
      expect(runtime_context_for(fixture, category: "tool")).to include(current_tool: fixture.tool)
      expect(runtime_context_for(fixture, category: "skills")).to include(current_skill_catalog: fixture.skill_catalog)
      expect(runtime_context_for(fixture, category: "test_suite")).to include(current_test_suite: fixture.test_suite)
      expect(runtime_context_for(fixture, category: "inventory")).to include(operation: fixture.operation)
    end
    # rubocop:enable RSpec/MultipleExpectations

    it "selects API channel context for API channel scenarios" do
      context = runtime_context_for(fixture, category: "channel", scenario_key: "channel-05")

      expect(context[:current_channel]).to eq(fixture.api_channel)
      expect(fixture.runtime_context_summary.dig(:operation, "id")).to eq(fixture.operation.id)
    end

    it "selects client channel context for normal channel scenarios" do
      context = runtime_context_for(fixture, category: "channel", scenario_key: "channel-01")

      expect(context[:current_channel]).to eq(fixture.client_channel)
    end

    it "summarizes non-record runtime context values" do
      unbuilt_fixture = described_class.new(
        tenant:,
        user: nil,
        test_case:,
        model_id: model_record.model_id,
        model_record:,
        token: "summary-token",
      )

      expect(unbuilt_fixture.runtime_context_summary[:user]).to eq("")
    end

    it "returns quickly when there are no channels to detach" do
      expect { fixture.send(:detach_fixture_chats!, []) }.not_to raise_error
    end

    it "ignores records that disappear during cleanup" do
      record = instance_double(Operation)
      allow(record).to receive(:destroy!).and_raise(ActiveRecord::RecordNotFound)

      expect(fixture.send(:destroy_record, record)).to be_nil
    end
  end

  def runtime_context_for(fixture, category:, scenario_key: "cleanup-01")
    test_case.update!(category:, scenario_key:)
    fixture.runtime_context_for
  end
end
