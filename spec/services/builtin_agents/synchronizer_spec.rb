# frozen_string_literal: true

require "rails_helper"

RSpec.describe BuiltinAgents::Synchronizer do
  def expected_agent_alpha_designer_keys
    [
      "mission_designer",
      "agent_designer",
      "tool_designer",
      "channel_designer",
      "skill_catalog_designer",
      "test_suite_designer",
    ]
  end

  describe ".ensure_present!" do
    it "creates Agent Alpha with all designer subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["agent_alpha"])

      agent_alpha = Agent.find_builtin_by_key("agent_alpha")
      designers = expected_agent_alpha_designer_keys.map { |key| Agent.find_builtin_by_key(key) }

      expect(agent_alpha.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(designers.map(&:thinking_effort).uniq).to eq(["none"])
      expect(agent_alpha.runtime_tool_keys).to eq(
    ["manage_record", "resources.list_resources", "web.web_search", "web.web_fetch"],
  )
      expect(agent_alpha.subagent_ids).to eq(designers.map(&:id))
      expect(agent_alpha.skill_catalogs.builtin.map(&:builtin_key)).to contain_exactly(
        "undercover-agents-admin",
        "undercover-agents-agents",
        "undercover-agents-channels",
        "undercover-agents-missions",
        "undercover-agents-skills",
        "undercover-agents-test-suites",
        "undercover-agents-tools",
        "undercover-agents-rag",
      )
    end

    it "enables Agent Alpha title generation by default", :aggregate_failures do
      described_class.ensure_present!(keys: ["agent_alpha"])

      agent_alpha = Agent.find_builtin_by_key("agent_alpha")

      expect(agent_alpha.capability_enabled?(:chat_title_generator)).to be(true)
      expect(agent_alpha.capability(:chat_title_generator).max_length)
        .to eq(Capabilities::TitleGenerator::DEFAULT_MAX_LENGTH)
    end

    it "creates mission_designer in Headquarter without configured subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["mission_designer"])

      mission_designer = Agent.find_builtin_by_key("mission_designer")

      expect(mission_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(mission_designer).to have_attributes(builtin: true, selectable: false, subagent_ids: [])
      expect(mission_designer.runtime_tool_keys).to include("resources.list_resources")
      expect(mission_designer.runtime_tool_keys).to include("web.web_search")
      expect(mission_designer.runtime_tool_keys).to include("web.web_fetch")
      expect(mission_designer.runtime_tool_keys).to include("mission_designer.validate_flow")
      expect(mission_designer.runtime_tool_keys).to include("mission_designer.run_debug", "mission_designer.read_run")
      expect(mission_designer.runtime_tool_keys).to include("records.manage_record", "navigation.navigate_to_page")
      expect(mission_designer.runtime_tool_keys & ["mission_designer.designer_handbook"]).to be_empty
      expect(mission_designer.skill_catalogs.builtin.map(&:builtin_key)).to eq(["undercover-agents-missions"])
    end

    it "creates agent_designer in Headquarter without configured subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["agent_designer"])

      agent_designer = Agent.find_builtin_by_key("agent_designer")

      expect(agent_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(agent_designer).to have_attributes(builtin: true, selectable: false, subagent_ids: [])
      expect(agent_designer.runtime_tool_keys).to include(
        "agent_designer.read_agent",
        "agent_designer.read_agent_chat",
        "agent_designer.debug_agent",
        "resources.list_resources",
        "web.web_search",
        "web.web_fetch",
        "agent_designer.manage_capability",
      )
      expect(agent_designer.runtime_tool_keys).to include("records.manage_record", "navigation.navigate_to_page")
      expect(agent_designer.skill_catalogs.builtin.map(&:builtin_key)).to eq(["undercover-agents-agents"])
    end

    it "creates tool_designer in Headquarter without configured subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["tool_designer"])

      tool_designer = Agent.find_builtin_by_key("tool_designer")

      expect(tool_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(tool_designer).to have_attributes(builtin: true, selectable: false, subagent_ids: [])
      expect(tool_designer.runtime_tool_keys).to include(
        "tool_designer.read_tool",
        "resources.list_resources",
        "web.web_search",
        "web.web_fetch",
        "tool_designer.tool_type_info",
        "tool_designer.manage_tool_action",
      )
      expect(tool_designer.runtime_tool_keys).to include("records.manage_record", "navigation.navigate_to_page")
      expect(tool_designer.skill_catalogs.builtin.map(&:builtin_key)).to eq(["undercover-agents-tools"])
    end

    it "creates channel_designer in Headquarter without configured subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["channel_designer"])

      channel_designer = Agent.find_builtin_by_key("channel_designer")

      expect(channel_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(channel_designer).to have_attributes(builtin: true, selectable: false, subagent_ids: [])
      expect(channel_designer.runtime_tool_keys).to include(
        "channel_designer.read_channel",
        "resources.list_resources",
        "web.web_search",
        "web.web_fetch",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
      expect(channel_designer.skill_catalogs.builtin.map(&:builtin_key)).to contain_exactly(
        "undercover-agents-admin",
        "undercover-agents-channels",
      )
    end

    it "creates skill_catalog_designer in Headquarter without configured subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["skill_catalog_designer"])

      skill_catalog_designer = Agent.find_builtin_by_key("skill_catalog_designer")

      expect(skill_catalog_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(skill_catalog_designer).to have_attributes(builtin: true, selectable: false, subagent_ids: [])
      expect(skill_catalog_designer.runtime_tool_keys).to include(
        "skill_catalog_designer.read_skill_catalog",
        "resources.list_resources",
        "web.web_search",
        "web.web_fetch",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
      expect(skill_catalog_designer.skill_catalogs.builtin.map(&:builtin_key)).to eq(["undercover-agents-skills"])
    end

    it "creates test_suite_designer in Headquarter with the mission and " \
       "agent designer subagents", :aggregate_failures do
      described_class.ensure_present!(keys: ["test_suite_designer"])

      test_suite_designer = Agent.find_builtin_by_key("test_suite_designer")
      subagents = [Agent.find_builtin_by_key("agent_designer"), Agent.find_builtin_by_key("mission_designer")]

      expect(test_suite_designer.operation.name).to eq(Operation::HEADQUARTER_NAME)
      expect(test_suite_designer).to have_attributes(builtin: true, selectable: false)
      expect(test_suite_designer.subagent_ids).to eq(subagents.map(&:id))
      expect(test_suite_designer.runtime_tool_keys).to include(
        "test_suite_designer.read_test_suite",
        "test_suite_designer.read_test_suite_run",
        "test_suite_designer.manage_test_case",
        "test_suite_designer.manage_test_suite_action",
        "resources.list_resources",
        "web.web_search",
        "web.web_fetch",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
      expect(test_suite_designer.skill_catalogs.builtin.map(&:builtin_key)).to contain_exactly(
        "undercover-agents-admin",
        "undercover-agents-agents",
        "undercover-agents-missions",
        "undercover-agents-test-suites",
      )
    end

    it "does not create unrelated helper builtins when mission_designer is requested" do
      described_class.ensure_present!(keys: ["mission_designer"])

      expect(Agent.find_builtin_by_key("code_assistant")).to be_nil
      expect(Agent.find_builtin_by_key("prompt_assistant")).to be_nil
      expect(Agent.find_builtin_by_key("dentaku_condition_writer")).to be_nil
    end

    it "removes stale builtin agents that no longer have a definition during full sync" do
      tenant = Tenant.default_tenant.tap(&:ensure_core_resources!)
      headquarter = tenant.headquarter_operation
      stale_agent = create(
        :agent,
        operation: headquarter,
        builtin: true,
        builtin_key: "dentaku_condition_writer",
        builtin_source: Rails.root.join("config/builtin_agents/dentaku_condition_writer.toml").to_s,
        selectable: false,
        agent_type: "expression_writer",
        name: "Expression Writer",
      )

      described_class.ensure_present!(tenant:)

      expect(Agent.find_by(id: stale_agent.id)).to be_nil
    end

    it "does not overwrite editable customizations during a normal sync" do
      described_class.ensure_present!(keys: ["agent_alpha"])
      agent = Agent.find_builtin_by_key("agent_alpha")
      agent.update!(name: "Custom Agent Alpha", instructions: "Custom instructions", temperature: 1.1)

      described_class.ensure_present!(keys: ["agent_alpha"])

      expect(agent.reload.name).to eq("Custom Agent Alpha")
      expect(agent.instructions).to eq("Custom instructions")
      expect(agent.temperature).to eq(1.1)
    end

    it "adds builtin default capabilities without overwriting existing capability customizations" do
      described_class.ensure_present!(keys: ["agent_alpha"])
      agent_alpha = Agent.find_builtin_by_key("agent_alpha")

      agent_alpha.set_capability_config(
        "chat_title_generator",
        { "max_length" => 12, "max_turns" => 1 },
        enabled: false,
      )
      agent_alpha.set_capability_config("memory", {}, enabled: true)
      agent_alpha.save!

      described_class.ensure_present!(keys: ["agent_alpha"])

      expect(agent_alpha.reload.capability_enabled?(:chat_title_generator)).to be(false)
      expect(agent_alpha.capability(:chat_title_generator).max_length).to eq(12)
      expect(agent_alpha.capability_enabled?(:memory)).to be(true)
    end

    it "returns an empty result when no definitions are loaded" do
      allow(BuiltinAgents::DefinitionLoader).to receive(:load_all).and_return([])

      result = described_class.ensure_present!

      expect(result.created_keys).to eq([])
      expect(result.restored_keys).to eq([])
    end

    it "raises when requested builtin keys are unknown" do
      allow(BuiltinAgents::DefinitionLoader).to receive(:load_all).and_return([])

      expect { described_class.ensure_present!(keys: ["missing_builtin"]) }
        .to raise_error("Unknown builtin agent keys: missing_builtin")
    end
  end

  describe ".restore_all!" do
    it "returns an empty result when no definitions are loaded" do
      allow(BuiltinAgents::DefinitionLoader).to receive(:load_all).and_return([])

      result = described_class.restore_all!

      expect(result.created_keys).to eq([])
      expect(result.restored_keys).to eq([])
    end
  end

  describe ".restore!" do
    it "restores editable attributes back to the builtin defaults" do
      described_class.ensure_present!(keys: ["agent_alpha"])
      agent = Agent.find_builtin_by_key("agent_alpha")
      definition = BuiltinAgents::DefinitionLoader.load_for(["agent_alpha"]).first

      agent.update!(name: "Custom Agent Alpha", instructions: "Custom instructions", temperature: 1.1)

      described_class.restore!("agent_alpha")

      expect(agent.reload.name).to eq(definition.name)
      expect(agent.instructions).to eq(definition.instructions)
      expect(agent.temperature).to eq(definition.temperature)
    end

    it "restores builtin capabilities back to the builtin defaults" do
      described_class.ensure_present!(keys: ["agent_alpha"])
      agent_alpha = Agent.find_builtin_by_key("agent_alpha")

      agent_alpha.set_capability_config(
        "chat_title_generator",
        { "max_length" => 12, "max_turns" => 1 },
        enabled: false,
      )
      agent_alpha.set_capability_config("memory", {}, enabled: true)
      agent_alpha.save!

      described_class.restore!("agent_alpha")

      expect(agent_alpha.reload.configuration.fetch("capabilities").keys).to eq(["chat_title_generator"])
      expect(agent_alpha.capability_enabled?(:chat_title_generator)).to be(true)
      expect(agent_alpha.capability(:chat_title_generator).max_length)
        .to eq(Capabilities::TitleGenerator::DEFAULT_MAX_LENGTH)
      expect(agent_alpha.capability_enabled?(:memory)).to be(false)
    end
  end

  describe "private helpers" do
    it "adds builtin capability defaults when an existing record has no configuration hash" do
      synchronizer = described_class.new(restore: false)
      agent = Struct.new(:configuration) do
        def new_record? = false
      end.new(nil)
      definition = instance_double(
        BuiltinAgents::Definition,
        key: "agent_alpha",
        capability_configs: { "chat_title_generator" => {} },
      )

      synchronizer.send(:apply_capability_assignments, agent, definition)

      expect(agent.configuration.fetch("capabilities").keys).to eq(["chat_title_generator"])
    end

    it "raises when a builtin agent references an unknown capability key" do
      synchronizer = described_class.new(restore: true)
      agent = create(:agent)
      definition = instance_double(
        BuiltinAgents::Definition,
        key: "agent_alpha",
        capability_configs: { "missing" => {} },
      )

      expect do
        synchronizer.send(:resolve_capability_configs, agent, definition)
      end.to raise_error("Unknown builtin capability keys: missing")
    end

    it "raises when a builtin capability configuration is invalid" do
      synchronizer = described_class.new(restore: true)
      agent = create(:agent)
      definition = instance_double(BuiltinAgents::Definition, key: "agent_alpha")

      expect do
        synchronizer.send(
          :normalize_capability_config,
          agent,
          definition,
          Capabilities::TitleGenerator,
          { "enabled" => false, "max_length" => 0 },
        )
      end.to raise_error(/Invalid builtin capability 'chat_title_generator' for 'agent_alpha'/)
    end

    it "supports capability configurators without an agent record writer" do
      synchronizer = described_class.new(restore: true)
      definition = instance_double(BuiltinAgents::Definition, key: "agent_alpha")
      capability_class = Class.new do
        def self.key = "dummy"

        def initialize(_attributes); end

        def valid? = true

        def to_configuration = { "mode" => "default" }
      end

      result = synchronizer.send(
        :normalize_capability_config,
        create(:agent),
        definition,
        capability_class,
        {},
      )

      expect(result).to eq("mode" => "default", "enabled" => true)
    end

    it "replaces malformed builtin capability entries with the shipped defaults" do
      synchronizer = described_class.new(restore: true)

      result = synchronizer.send(
        :merge_builtin_capabilities,
        { "chat_title_generator" => "broken" },
        { "chat_title_generator" => { "enabled" => true } },
      )

      expect(result).to eq("chat_title_generator" => { "enabled" => true })
    end

    it "skips keys that were already expanded while resolving builtin dependencies" do
      synchronizer = described_class.new(keys: ["mission_designer"], restore: false)
      shared = instance_double(BuiltinAgents::Definition, key: "shared_subagent", subagent_keys: [])
      mission_designer = instance_double(
        BuiltinAgents::Definition,
        key: "mission_designer",
        subagent_keys: ["shared_subagent", "shared_subagent"],
      )

      result = synchronizer.send(
        :expand_requested_definitions,
        {
          "mission_designer" => mission_designer,
          "shared_subagent" => shared,
        },
      )

      expect(result.map(&:key)).to eq(["mission_designer", "shared_subagent"])
    end

    it "raises when a requested builtin depends on an unknown subagent" do
      synchronizer = described_class.new(keys: ["mission_designer"], restore: false)
      definition = instance_double(
        BuiltinAgents::Definition,
        key: "mission_designer",
        subagent_keys: ["missing_subagent"],
      )

      expect do
        synchronizer.send(:expand_requested_definitions, { "mission_designer" => definition })
      end.to raise_error("Unknown builtin agent keys: missing_subagent")
    end

    it "ignores missing subagent records while syncing builtin subagents" do
      synchronizer = described_class.new(restore: true)
      agent = create(:agent)
      definition = instance_double(
        BuiltinAgents::Definition,
        key: agent.builtin_key || agent.id.to_s,
        subagent_keys: ["missing"],
      )

      expect do
        synchronizer.send(:sync_subagents!, [definition], { definition.key => agent })
      end.not_to raise_error
    end

    it "updates subagent ids when the configured builtin dependencies change" do
      synchronizer = described_class.new(restore: true)
      agent = create(:agent)
      subagent = create(:agent)
      definition = instance_double(
        BuiltinAgents::Definition,
        key: agent.id.to_s,
        subagent_keys: [subagent.id.to_s],
      )

      synchronizer.send(
        :sync_subagents!,
        [definition],
        { definition.key => agent, subagent.id.to_s => subagent },
      )

      expect(agent.reload.subagent_ids).to eq([subagent.id])
    end

    it "raises when a builtin agent references an unknown builtin skill catalog" do
      synchronizer = described_class.new(restore: true)

      expect do
        synchronizer.send(:resolve_skill_catalog_ids, ["missing-catalog"], {})
      end.to raise_error("Unknown builtin skill catalog keys: missing-catalog")
    end

    it "skips subagent sync entries when the target agent is missing" do
      synchronizer = described_class.new(restore: true)
      definition = instance_double(BuiltinAgents::Definition, key: "code_assistant", subagent_keys: [])

      expect do
        synchronizer.send(:sync_subagents!, [definition], {})
      end.not_to raise_error
    end
  end
end
