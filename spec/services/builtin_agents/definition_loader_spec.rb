# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe BuiltinAgents::DefinitionLoader do
  def expected_agent_alpha_skill_catalog_keys
    [
      "undercover-agents-admin",
      "undercover-agents-agents",
      "undercover-agents-channels",
      "undercover-agents-missions",
      "undercover-agents-skills",
      "undercover-agents-test-suites",
      "undercover-agents-tools",
      "undercover-agents-rag",
    ]
  end

  def expected_agent_alpha_instruction_fragments
    expected_agent_alpha_discovery_fragments + expected_agent_alpha_delegation_fragments
  end

  def expected_agent_alpha_discovery_fragments
    [
      "Supported kinds: `agent_types`, `capabilities`, `models`, `default_models`, " \
      "`tool_types`, `tools`, `agents`, `missions`, `channels`, `clients`, `skill_catalogs`, " \
      "`skills`, `rag_flows`, `connectors`, `test_suites`",
      "take at most one narrow discovery step",
      "trailing `<child_result>` JSON block with `status`, `record_ids`, `warnings`, and `blockers`",
      "at most one follow-up step",
      "use `safe_web_search`",
      "Connector creation is out of scope",
    ]
  end

  def expected_agent_alpha_delegation_fragments
    [
      "create a mission, create an agent, create a tool, create a channel, " \
      "create a skill catalog, create a skill, create a test suite, or create a test, delegate directly",
      "Do NOT call `list_resources` first for creation requests",
      "explicitly asks for an inventory, list, or availability check before creation",
      "designer sub-agent already returned an error and you now need to investigate the failure",
      "Mission → Mission Designer",
      "Agent → Agent Designer",
      "Tool → Tool Designer",
      "Channel → Channel Designer",
      "Skill Catalog / Skill → Skill Catalog Designer",
      "Test Suite / Test → Test Suite Designer",
      "preserve those as runtime payload inputs for the Mission Designer",
      "tell the designer to hardcode values unless the user explicitly asked to change the workflow",
    ]
  end

  def load_definition_from_toml(contents)
    Dir.mktmpdir do |dir|
      path = Pathname.new(File.join(dir, "builtin.toml"))
      path.write(contents)
      described_class.send(:load_file, path)
    end
  end

  def expect_agent_designer_attributes(definition)
    expect(definition).to have_attributes(
      agent_type: "agent_designer",
      llm_config_source: "system_preference",
      subagent_keys: [],
      skill_catalog_keys: ["undercover-agents-agents"],
    )
    expect(definition.input_schema.pluck("variable_name"))
      .to contain_exactly("agent_name", "agent_description")
  end

  def expect_agent_designer_tools_and_instructions(definition)
    expect(definition.tool_keys).to include(
      "agent_designer.read_agent",
      "agent_designer.read_agent_chat",
      "agent_designer.debug_agent",
      "resources.list_resources",
      "web.safe_web_search",
      "agent_designer.manage_capability",
      "records.manage_record",
      "navigation.navigate_to_page",
    )
    expect(definition.instructions).to include(
      "manage_capability",
      "assigned_tool_ids",
      "subagent_ids",
      "read_agent_chat",
      "debug_agent",
    )
  end

  describe ".load_all" do
    subject(:definitions) { described_class.load_all.index_by(&:key) }

    it "loads application and plugin builtin agent definitions" do
      expect(definitions.keys).to include(
        "agent_designer",
        "channel_designer",
        "mission_designer",
        "test_suite_designer",
        "skill_catalog_designer",
        "tool_designer",
        "test_evaluator",
        "chat_title_generator",
        "sql_query_agent",
      )
    end

    it "loads all builtin agents with explicit thinking disabled" do
      expect(definitions.values.map(&:thinking_effort).uniq).to eq(["none"])
    end

    it "resolves mission-designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("mission_designer")

      expect(definition).to have_attributes(
        agent_type: "mission_designer",
        llm_config_source: "system_preference",
        subagent_keys: [],
        skill_catalog_keys: ["undercover-agents-missions"],
      )
      expect(definition.tool_keys).to include("resources.list_resources", "web.safe_web_search")
      expect(definition.tool_keys).to include("mission_designer.validate_flow")
      expect(definition.tool_keys).to include("mission_designer.run_debug", "mission_designer.read_run")
      expect(definition.tool_keys).to include("records.manage_record", "navigation.navigate_to_page")
      expect(definition.tool_keys & ["mission_designer.designer_handbook", "mission_designer.generate_code"])
        .to be_empty
      expect(definition.input_schema.pluck("variable_name"))
        .to contain_exactly("mission_name", "mission_description")
      expect(definition.instructions).to include("mission")
    end

    it "loads Agent Alpha with the designer subagents", :aggregate_failures do
      definition = definitions.fetch("agent_alpha")
      expected_subagents = [
        "mission_designer",
        "agent_designer",
        "tool_designer",
        "channel_designer",
        "skill_catalog_designer",
        "test_suite_designer",
      ]

      expect(definition.capability_configs.keys).to eq(["chat_title_generator"])
      expect(definition.tool_keys).to eq(["resources.list_resources", "web.safe_web_search"])
      expect(definition.subagent_keys).to eq(expected_subagents)
    end

    it "loads Agent Alpha guidance and skill catalogs", :aggregate_failures do
      definition = definitions.fetch("agent_alpha")

      expect(definition.skill_catalog_keys).to eq(expected_agent_alpha_skill_catalog_keys)
      expected_agent_alpha_instruction_fragments.each do |fragment|
        expect(definition.instructions).to include(fragment)
      end
    end

    it "loads agent_designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("agent_designer")

      expect_agent_designer_attributes(definition)
      expect_agent_designer_tools_and_instructions(definition)
    end

    it "loads tool_designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("tool_designer")

      expect(definition).to have_attributes(
        agent_type: "tool_designer",
        llm_config_source: "system_preference",
        subagent_keys: [],
        skill_catalog_keys: ["undercover-agents-tools"],
      )
      expect(definition.tool_keys).to include(
        "tool_designer.read_tool",
        "resources.list_resources",
        "web.safe_web_search",
        "tool_designer.tool_type_info",
        "tool_designer.manage_tool_action",
      )
      expect(definition.tool_keys).to include("records.manage_record", "navigation.navigate_to_page")
      expect(definition.input_schema.pluck("variable_name"))
        .to contain_exactly("tool_name", "tool_description", "tool_type", "tool_type_label")
      expect(definition.instructions).to include("toolable_attributes")
      expect(definition.instructions).to include("manage_tool_action")
    end

    it "loads channel_designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("channel_designer")

      expect(definition).to have_attributes(
        agent_type: "channel_designer",
        llm_config_source: "system_preference",
        subagent_keys: [],
        skill_catalog_keys: ["undercover-agents-admin", "undercover-agents-channels"],
      )
      expect(definition.tool_keys).to include(
        "channel_designer.read_channel",
        "channel_designer.manage_channel_action",
        "resources.list_resources",
        "web.safe_web_search",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
      expect(definition.input_schema.pluck("variable_name")).to contain_exactly(
        "channel_name",
        "channel_type",
        "channel_title",
      )
      expect(definition.instructions).to include(
        "resource=\"channel\"",
        "page: \"preview\"",
        "list_resources(kind: \"channels\")",
      )
    end

    it "loads skill_catalog_designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("skill_catalog_designer")

      expect(definition).to have_attributes(
        agent_type: "skill_catalog_designer",
        llm_config_source: "system_preference",
        subagent_keys: [],
        skill_catalog_keys: ["undercover-agents-skills"],
      )
      expect(definition.tool_keys).to include(
        "skill_catalog_designer.read_skill_catalog",
        "skill_catalog_designer.read_skill",
        "skill_catalog_designer.manage_skill",
        "skill_catalog_designer.manage_skill_catalog_action",
        "resources.list_resources",
        "web.safe_web_search",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
    end

    it "loads skill_catalog_designer instructions from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("skill_catalog_designer")

      expect(definition.input_schema.pluck("variable_name"))
        .to contain_exactly("skill_catalog_name", "skill_catalog_description")
      expect(definition.instructions).to include(
        "resource=\"skill_catalog\"",
        "read_skill_catalog",
        "read_skill",
        "manage_skill",
        "manage_skill_catalog_action",
      )
    end

    it "loads test_suite_designer metadata from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("test_suite_designer")

      expect(definition).to have_attributes(
        agent_type: "test_suite_designer",
        llm_config_source: "system_preference",
        subagent_keys: ["agent_designer", "mission_designer"],
        skill_catalog_keys: [
          "undercover-agents-admin",
          "undercover-agents-agents",
          "undercover-agents-missions",
          "undercover-agents-test-suites",
        ],
      )
      expect(definition.tool_keys).to include(
        "test_suite_designer.read_test_suite",
        "test_suite_designer.read_test_suite_run",
        "test_suite_designer.manage_test_case",
        "test_suite_designer.manage_test_suite_action",
        "resources.list_resources",
        "web.safe_web_search",
        "records.manage_record",
        "navigation.navigate_to_page",
      )
    end

    it "loads test_suite_designer instructions from the TOML definition", :aggregate_failures do
      definition = definitions.fetch("test_suite_designer")

      expect(definition.input_schema.pluck("variable_name"))
        .to contain_exactly("test_suite_name", "test_suite_description", "test_suite_type")
      expect(definition.instructions).to include(
        "Current test suite: {{test_suite_name}}",
        "Current test suite description: {{test_suite_description}}",
        "Current test suite type: {{test_suite_type}}",
        "resource=\"test_suite\"",
        "manage_test_case",
        "manage_test_suite_action",
        "read_test_suite_run",
        "expected_child_builtin_key",
        "forbidden_keywords",
        ["%", "{benchmark_agent_name}"].join,
        "inventory",
        "delegate once to Agent Designer",
        "delegate once to Mission Designer",
      )
    end

    it "does not advertise helper subagents in the mission-designer instructions" do
      definition = definitions.fetch("mission_designer")

      expect(definition.instructions).not_to include("Sub-agents")
    end

    it "includes mission handbook skill guidance in the mission-designer instructions" do
      definition = definitions.fetch("mission_designer")

      expect(definition.instructions).to include("mission-designer-handbook")
    end

    it "includes workflow-shape guidance in the mission-designer instructions" do
      definition = definitions.fetch("mission_designer")

      expect(definition.instructions).to include(
        "scalars only",
        "disabled edges and nodes never block joins",
        "json_extract_2",
        "Prefer the narrowest built-in node",
        "let the edge carry the incoming user data into the `llm` node",
        "`code` is the last resort",
      )
    end

    it "includes validation guidance in the mission-designer instructions", :aggregate_failures do
      definition = definitions.fetch("mission_designer")

      expect(definition.instructions).to include(
        "Do not immediately rerun `validate_flow`",
        "manage_record",
        "page: \"designer\"",
        "Pass `mission_id` to patch a mission you just created",
        "Never call `run_mission_debug` unless the user explicitly asked to run, debug, execute, or test the mission.",
        "treat concrete sample usernames, emails, IDs, slugs, and similar values as runtime payload inputs",
        "Never hardcode a sample test value into node config",
        "Structured mission-tool arguments must be strict JSON",
        "stop guessing alternate syntaxes",
        "Do not replace a requested dynamic input or reference with a static placeholder",
        "`temp_id` is only for same-patch node and edge references",
        "Never create blank or sentinel globals",
        "Do not use `variables` arrays or invent other config aliases",
        "Do not call `list_node_variables`, `read_mission_flow`, or send another patch just to " \
        "double-check the same flow",
        "Do not invent optional convenience inputs, override knobs, or debug toggles",
      )
      expect(definition.instructions).to include(
        "Wrap it in `{{...}}` only when the target field is template-valued.",
        "Non-template fields such as `selected_variables`, `expected_variables`, " \
        "collection refs, and formulas use the bare identifier",
      )
    end

    it "loads plugin-provided builtin agent definitions" do
      title_generator = definitions.fetch("chat_title_generator")
      sql_query_agent = definitions.fetch("sql_query_agent")

      expect(title_generator.input_schema.pluck("variable_name")).to eq(["max_length"])
      expect(sql_query_agent.tool_keys).to eq([])
      expect(sql_query_agent.selectable).to be(false)
    end

    it "raises when duplicate builtin agent keys are discovered" do
      duplicate = instance_double(BuiltinAgents::Definition, key: "duplicate")
      allow(described_class).to receive(:definition_paths).and_return(["a.toml", "b.toml"])
      allow(described_class).to receive(:load_file).and_return(duplicate, duplicate)

      expect { described_class.load_all }
        .to raise_error("Duplicate builtin agent keys detected: duplicate")
    end

    it "reuses parsed definitions when definition files are unchanged" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(File.join(dir, "cached_builtin.toml"))
        path.write(<<~TOML)
          key = "cached"
          name = "Cached"
        TOML

        allow(described_class).to receive(:definition_paths).and_return([path.to_s])
        allow(described_class).to receive(:load_file).and_call_original

        first = described_class.load_all
        second = described_class.load_all

        expect(first.map(&:key)).to eq(["cached"])
        expect(second.map(&:key)).to eq(["cached"])
        expect(described_class).to have_received(:load_file).once
      end
    end
  end

  describe "private helpers" do
    it "defaults optional fields when toml omits them" do
      definition = load_definition_from_toml(<<~TOML)
        key = "defaulted"
        name = "Defaulted"
      TOML

      expect(definition.enabled).to be(true)
      expect(definition.selectable).to be(false)
      expect(definition.instructions).to eq("")
      expect(definition.thinking_effort).to be_nil
      expect(definition.capability_configs).to eq({})
    end

    it "loads tools, capabilities, subagents, and inline input_schema arrays from toml" do
      definition = load_definition_from_toml(inline_arrays_toml)

      expect(definition.tool_keys).to eq(["demo.tool"])
      expect(definition.capability_configs).to eq({ "chat_title_generator" => {} })
      expect(definition.subagent_keys).to eq(["child_helper"])
      expect(definition.skill_catalog_keys).to eq(["undercover-agents-agents", "undercover-agents-tools"])
      expect(definition.input_schema).to eq(
        [{
          "variable_name" => "task",
          "label" => "Task",
          "field_type" => "string",
          "required" => true,
        }],
      )
    end

    it "loads capability configuration tables from toml" do
      definition = load_definition_from_toml(<<~TOML)
        key = "capabilities"
        name = "Capabilities"

        [capabilities.chat_title_generator]
        max_length = 18
        max_turns = 2
      TOML

      expect(definition.capability_configs).to eq(
        "chat_title_generator" => {
          "max_length" => 18,
          "max_turns" => 2,
        },
      )
    end

    it "loads inline capability entries keyed by capability" do
      definition = load_definition_from_toml(<<~TOML)
        key = "inline_capabilities"
        name = "Inline Capabilities"
        capabilities = [{ capability = "chat_title_generator", max_length = 18 }]
      TOML

      expect(definition.capability_configs).to eq(
        "chat_title_generator" => {
          "max_length" => 18,
        },
      )
    end

    it "normalizes boolean capability table values" do
      definition = load_definition_from_toml(<<~TOML)
        key = "boolean_capabilities"
        name = "Boolean Capabilities"

        [capabilities]
        chat_title_generator = true
        memory = false
      TOML

      expect(definition.capability_configs).to eq(
        "chat_title_generator" => {},
        "memory" => { "enabled" => false },
      )
    end

    it "prefers inline instructions when present" do
      definition = load_definition_from_toml(<<~TOML)
        key = "inline"
        name = "Inline"
        instructions = '''
        Use inline text
        '''
      TOML

      expect(definition.instructions).to eq("Use inline text")
    end

    it "reads multiline instructions from the toml definition" do
      definition = load_definition_from_toml(<<~TOML)
        key = "multiline"
        name = "Multiline"
        instructions = '''
        First line
        Second line
        '''
      TOML

      expect(definition.instructions).to eq("First line\nSecond line")
    end

    it "raises when a toml file is blank" do
      expect { load_definition_from_toml("") }.to raise_error(KeyError)
    end

    it "raises when capabilities use an unsupported top-level format" do
      expect do
        load_definition_from_toml(<<~TOML)
          key = "invalid_top_level"
          name = "Invalid Top Level"
          capabilities = 123
        TOML
      end.to raise_error(ArgumentError, /Invalid builtin capabilities format/)
    end

    it "raises when inline capability entries omit their key" do
      expect do
        load_definition_from_toml(<<~TOML)
          key = "missing_inline_key"
          name = "Missing Inline Key"
          capabilities = [{ max_length = 18 }]
        TOML
      end.to raise_error(ArgumentError, /Builtin capability entries must include `key`/)
    end

    it "raises when inline capability entries use an unsupported entry type" do
      expect do
        load_definition_from_toml(<<~TOML)
          key = "invalid_inline_entry"
          name = "Invalid Inline Entry"
          capabilities = [123]
        TOML
      end.to raise_error(ArgumentError, /Invalid builtin capability entry/)
    end

    it "raises when a capability table value is not a boolean or table" do
      expect do
        load_definition_from_toml(<<~TOML)
          key = "invalid_table_value"
          name = "Invalid Table Value"

          [capabilities]
          chat_title_generator = 123
        TOML
      end.to raise_error(ArgumentError, /must map to a table or boolean/)
    end

    it "accepts unique builtin keys" do
      definitions = [
        instance_double(BuiltinAgents::Definition, key: "first"),
        instance_double(BuiltinAgents::Definition, key: "second"),
      ]

      expect { described_class.send(:detect_duplicate_keys!, definitions) }.not_to raise_error
    end
  end

  def inline_arrays_toml
    <<~TOML
      key = "inline_arrays"
      name = "Inline Arrays"
      tools = ["demo.tool"]
      capabilities = ["chat_title_generator"]
      subagents = ["child_helper"]
      skill_catalogs = ["undercover-agents-agents", "undercover-agents-tools"]
      input_schema = [
        { variable_name = "task", label = "Task", field_type = "string", required = true },
      ]
    TOML
  end
end
