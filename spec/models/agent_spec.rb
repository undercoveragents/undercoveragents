# frozen_string_literal: true

# == Schema Information
#
# Table name: agents
# Database name: primary
#
#  id            :bigint           not null, primary key
#  agent_type    :string
#  builtin       :boolean          default(FALSE), not null
#  configuration :jsonb            not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_agents_on_agent_type                  (agent_type)
#  index_agents_on_operation_and_name          (operation_id,name) UNIQUE
#  index_agents_on_operation_id                (operation_id)
#  index_agents_on_slug                        (slug) UNIQUE
#  index_agents_on_type_and_operation_builtin  (agent_type,operation_id) UNIQUE WHERE (builtin = true)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
require "rails_helper"

RSpec.describe Agent do
  describe "associations" do
    it { is_expected.to have_many(:chats).dependent(:destroy) }
    it { is_expected.to have_many(:test_suites).dependent(:destroy) }
  end

  describe "validations" do
    subject(:agent) { build(:agent) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:operation_id) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }

    it "validates description length" do
      agent.description = "x" * 501
      expect(agent).not_to be_valid
      expect(agent.errors[:description]).to include("is too long (maximum is 500 characters)")
    end

    it "does not limit instructions length" do
      agent.instructions = "x" * 10_001

      expect(agent).to be_valid
    end

    it "validates model_id presence" do
      agent.model_id = nil
      expect(agent).not_to be_valid
      expect(agent.errors[:model_id]).to include("can't be blank")
    end

    it "validates model_id length" do
      agent.model_id = "x" * 201
      expect(agent).not_to be_valid
      expect(agent.errors[:model_id]).to include("is too long (maximum is 200 characters)")
    end

    it "validates temperature presence" do
      agent.configuration = agent.configuration.merge("temperature" => nil)
      expect(agent).not_to be_valid
      expect(agent.errors[:temperature]).to include("can't be blank")
    end

    it "validates temperature range" do
      agent.temperature = -0.1
      expect(agent).not_to be_valid
      expect(agent.errors[:temperature]).to include("must be greater than or equal to 0.0")

      agent.temperature = 2.1
      expect(agent).not_to be_valid
      expect(agent.errors[:temperature]).to include("must be less than or equal to 2.0")
    end

    it "validates agent_type length" do
      agent.agent_type = "x" * 101

      expect(agent).not_to be_valid
      expect(agent.errors[:agent_type]).to include("is too long (maximum is 100 characters)")
    end

    it "validates llm_config_source inclusion" do
      agent.llm_config_source = "unknown"

      expect(agent).not_to be_valid
      expect(agent.errors[:llm_config_source]).to include("is not included in the list")
    end

    it "requires builtin_key for builtin agents" do
      agent.builtin = true
      agent.builtin_key = nil

      expect(agent).not_to be_valid
      expect(agent.errors[:builtin_key]).to include("can't be blank for builtin agents")
    end

    it "validates input schema field types" do
      agent.input_schema = [{ variable_name: "file", label: "File", field_type: "invalid" }]

      expect(agent).not_to be_valid
      expect(agent.errors[:input_schema]).to include("field #1 has an invalid field_type")
    end

    it "validates input schema fields include a variable name and label" do
      agent.input_schema = [{}]

      expect(agent).not_to be_valid
      expect(agent.errors[:input_schema]).to include(
        "field #1 must include a variable_name",
        "field #1 must include a label",
      )
    end

    it "validates llm_connector_id references an llm provider" do
      agent.llm_connector = create(:connector, :sql_database, :enabled)

      expect(agent).not_to be_valid
      expect(agent.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "validates thinking_effort inclusion" do
      agent.thinking_effort = "extreme"

      expect(agent).not_to be_valid
      expect(agent.errors[:thinking_effort]).to include("is not included in the list")
    end

    it "validates thinking_budget is positive" do
      agent.thinking_budget = 0

      expect(agent).not_to be_valid
      expect(agent.errors[:thinking_budget]).to include("must be greater than 0")
    end

    it "validates custom llm params json" do
      agent.custom_llm_params = "not-json"

      expect(agent).not_to be_valid
      expect(agent.errors[:custom_llm_params].first).to include("must be valid JSON")
    end

    it "validates model routing config json" do
      agent.model_routing_config = '{"strategy":"fallback"'

      expect(agent).not_to be_valid
      expect(agent.errors[:model_routing_config].first).to include("must be valid JSON")
    end
  end

  describe "scopes" do
    let!(:enabled_agent) { create(:agent, :enabled) }
    let!(:disabled_agent) { create(:agent, :disabled) }
    let!(:builtin_agent) do
      create(:agent, builtin: true, builtin_key: "code_assistant", selectable: false, enabled: false)
    end

    describe ".enabled" do
      it "returns only enabled agents" do
        expect(described_class.enabled).to include(enabled_agent)
        expect(described_class.enabled).not_to include(disabled_agent, builtin_agent)
      end
    end

    describe ".disabled" do
      it "returns only disabled agents" do
        expect(described_class.disabled).to include(disabled_agent, builtin_agent)
        expect(described_class.disabled).not_to include(enabled_agent)
      end
    end

    describe ".ordered" do
      it "returns agents ordered by name" do
        expect(described_class.ordered).to eq(described_class.order(:name))
      end
    end

    describe ".builtin" do
      it "returns only builtin agents" do
        expect(described_class.builtin).to include(builtin_agent)
        expect(described_class.builtin).not_to include(enabled_agent)
      end
    end

    describe ".user_created" do
      it "returns only non-builtin agents" do
        expect(described_class.user_created).to include(enabled_agent, disabled_agent)
        expect(described_class.user_created).not_to include(builtin_agent)
      end
    end

    describe ".selectable" do
      it "returns agents that are not explicitly hidden" do
        expect(described_class.selectable).to include(enabled_agent, disabled_agent)
        expect(described_class.selectable).not_to include(builtin_agent)
      end
    end

    describe ".find_builtin_by_key" do
      it "returns the first builtin agent when no tenant is available" do
        tenant = create(:tenant)
        connector = create(:connector, :llm_provider, :enabled, tenant:)
        operation = create(:operation, tenant:)
        builtin_key = "coverage_builtin_agent"
        agent = create(
          :agent,
          operation:,
          llm_connector: connector,
          builtin: true,
          builtin_key:,
          selectable: false,
          enabled: false,
        )
        allow(Tenant).to receive(:default_tenant).and_return(nil)

        expect(described_class.find_builtin_by_key(builtin_key, tenant: nil)).to eq(agent)
      end
    end
  end

  describe "configuration helpers" do
    it "stores a nil temperature when explicitly cleared" do
      agent = build(:agent)

      agent.temperature = nil

      expect(agent.configuration["temperature"]).to be_nil
    end

    it "stores a nil thinking budget when explicitly cleared" do
      agent = build(:agent)

      agent.thinking_budget = ""

      expect(agent.configuration["thinking_budget"]).to be_nil
    end

    it "normalizes custom llm params into configuration" do
      agent = build(:agent)

      agent.custom_llm_params = '{"top_p":0.9}'

      expect(agent.custom_llm_params).to eq({ "top_p" => 0.9 })
      expect(agent.custom_llm_params_json).to include('"top_p": 0.9')
    end

    it "clears custom llm params when blank" do
      agent = build(:agent)

      agent.custom_llm_params = ""

      expect(agent.configuration).not_to have_key("custom_llm_params")
      expect(agent.custom_llm_params_json).to eq("")
    end

    it "returns a blank custom params json string when unset" do
      agent = build(:agent)

      expect(agent.custom_llm_params_json).to eq("")
    end

    it "pretty prints persisted custom llm params when no form input override exists" do
      agent = build(:agent)
      agent.configuration = agent.configuration.merge("custom_llm_params" => { "top_p" => 0.9 })

      expect(agent.custom_llm_params_json).to include('"top_p": 0.9')
    end

    it "returns an empty invalid-json echo for non-string values" do
      agent = build(:agent)

      expect(agent.send(:custom_llm_params_json_input, {})).to eq("")
    end

    it "normalizes model routing config into configuration" do
      agent = build(:agent)
      fallback_connector = create(:connector, :llm_provider, :enabled, tenant: agent.tenant)

      agent.model_routing_config = {
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => fallback_connector.id, "model_id" => "gpt-4.1-mini" }],
      }.to_json

      expect(agent.model_routing_config).to eq(
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => fallback_connector.id, "model_id" => "gpt-4.1-mini" }],
      )
      expect(agent.model_routing_config_json).to include('"strategy": "fallback"')
    end

    it "clears model routing config when blank" do
      agent = build(:agent)

      agent.model_routing_config = ""

      expect(agent.configuration).not_to have_key("model_routing_config")
      expect(agent.model_routing_config_json).to eq("")
    end

    it "normalizes builtin tool keys and input schema" do
      agent = build(:agent)
      agent.runtime_tool_keys = ["mission_designer.validate_flow", nil, ""]
      agent.input_schema = { variable_name: "name", label: "Name", required: false }

      expect(agent.runtime_tool_keys).to eq(["mission_designer.validate_flow"])
      expect(agent.configuration["tools"]).to eq(["mission_designer.validate_flow"])
      expect(agent.configuration).not_to have_key("runtime_tool_keys")
      expect(agent.input_schema).to eq([
                                         {
                                           "variable_name" => "name",
                                           "label" => "Name",
                                           "field_type" => "string",
                                           "required" => false,
                                           "config" => {},
                                         },
                                       ])
    end

    it "returns an empty input schema for invalid json" do
      agent = build(:agent)
      agent.input_schema = "not valid json"

      expect(agent.input_schema).to eq([])
    end

    it "drops input schema entries that do not behave like hashes" do
      agent = build(:agent)
      agent.input_schema = [Object.new]

      expect(agent.input_schema).to eq([])
    end

    it "returns builtin_source when present" do
      agent = build(:agent, builtin_source: "/tmp/code_assistant.toml")

      expect(agent.builtin_source).to eq("/tmp/code_assistant.toml")
    end

    it "stores skill catalog ids and resolves assigned catalogs" do
      skill_catalog = create(:skill_catalog)
      agent = build(:agent, operation: skill_catalog.operation)

      agent.skill_catalog_ids = [skill_catalog.id]

      expect(agent.skill_catalog_ids).to eq([skill_catalog.id])
      expect(agent.skill_catalogs).to include(skill_catalog)
    end

    it "resolves llm context from system preferences" do
      connector = create(:connector, :llm_provider, :enabled)
      create(:system_preference, llm_connector: connector, model_id: "gpt-4.1")
      agent = build(:agent, llm_connector: nil, llm_config_source: "system_preference")
      preference = SystemPreference.current
      allow(SystemPreference).to receive(:current).and_return(preference)
      allow(preference).to receive(:configured?).and_return(true)

      expect(agent.resolve_llm_context).to be_a(RubyLLM::Context)
    end

    it "returns nil for system preference context when unconfigured" do
      create(:system_preference)
      agent = build(:agent, llm_connector: nil, llm_config_source: "system_preference")
      allow(SystemPreference.current).to receive(:configured?).and_return(false)

      expect(agent.resolve_llm_context).to be_nil
    end

    it "resolves llm context from the assigned connector" do
      connector = create(:connector, :llm_provider, :enabled)
      agent = build(:agent, llm_connector: connector)

      expect(agent.resolve_llm_context).to be_a(RubyLLM::Context)
    end

    it "uses system preference values for resolved model and connector" do
      connector = create(:connector, :llm_provider, :enabled)
      create(:system_preference, llm_connector: connector, model_id: "gpt-4.1")
      agent = build(:agent, llm_connector: nil, model_id: nil, llm_config_source: "system_preference")

      expect(agent.resolved_model_id).to eq("gpt-4.1")
      expect(agent.resolved_llm_connector).to eq(connector)
    end

    it "uses direct agent configuration for resolved model and connector" do
      connector = create(:connector, :llm_provider, :enabled)
      agent = build(:agent, llm_connector: connector, model_id: "gpt-4.1", llm_config_source: "agent")

      expect(agent.resolved_model_id).to eq("gpt-4.1")
      expect(agent.resolved_llm_connector).to eq(connector)
    end
  end

  describe "#tools" do
    it "adds skill discovery and activation tools when the agent has attached skill catalogs" do
      skill_catalog = create(:skill_catalog)
      skill = create(:skill, skill_catalog:, name: "deep-research-playbook")
      create(:skill_resource, skill:, relative_path: "references/guide.md")
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      tool_names = agent.tools.map(&:name)
      instructions = agent.build_full_instructions

      expect(tool_names).to include("list_available_skills", "activate_skill", "read_skill_resource")
      expect(instructions).to include("<available_skill_catalogs>")
      expect(instructions).to include(skill_catalog.name)
      expect(instructions).to include("list_available_skills")
      expect(instructions).not_to include(skill.name)
    end

    it "omits the resource reader when no bundled resources are present" do
      skill_catalog = create(:skill_catalog)
      create(:skill, skill_catalog:)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      expect(agent.tools.map(&:name)).to include("list_available_skills", "activate_skill")
      expect(agent.tools.map(&:name)).not_to include("read_skill_resource")
    end

    it "rejects skill catalogs from another operation" do
      foreign_catalog = create(:skill_catalog)
      agent = build(:agent, operation: create(:operation))

      agent.skill_catalog_ids = [foreign_catalog.id]

      expect(agent).not_to be_valid
      expect(agent.errors[:skill_catalog_ids]).to include("must belong to the same operation as the agent")
    end

    it "rejects unknown skill catalog ids" do
      agent = build(:agent)

      agent.skill_catalog_ids = [999_999]

      expect(agent).not_to be_valid
      expect(agent.errors[:skill_catalog_ids]).to include("contain unknown skill catalogs")
    end

    it "returns McpServerTool instances for enabled MCP server tools" do
      local_agent = create(:agent)
      connector = create(:connector, :mcp_server, :enabled)
      mcp_server = create(:tools_mcp_server, connector:)
      tool = create(:tool, :enabled, toolable: mcp_server)
      local_agent.update!(tool_ids: [tool.id])

      allow(McpServerTool).to receive(:for_tool).and_return([])

      local_agent.tools
      expect(McpServerTool).to have_received(:for_tool)
    end

    it "returns SqlQueryTool instances for enabled SQL query tools" do
      agent = create(:agent, :with_sql_tool)

      tools = agent.tools
      expect(tools).to be_an(Array)
      expect(tools.size).to eq(1)
      expect(tools.first).to be_a(SqlQueryTool)
    end

    it "returns RagQueryTool instances for enabled RAG query tools" do
      agent = create(:agent)
      connector = create(:connector, :sql_database, :enabled)
      rag_query = create(:tools_rag_query, :with_llm, connector:)
      tool = create(:tool, :enabled, toolable: rag_query)
      agent.update!(tool_ids: [tool.id])

      tools = agent.tools
      expect(tools.size).to eq(1)
      expect(tools.first).to be_a(RagQueryTool)
    end

    it "returns RagFlowTool instances for enabled RAG flow tools" do
      agent = create(:agent)
      rag_flow_toolable = create(:tools_rag_flow)
      tool = create(:tool, :enabled, toolable: rag_flow_toolable)
      agent.update!(tool_ids: [tool.id])

      tools = agent.tools
      expect(tools.size).to eq(1)
      expect(tools.first).to be_a(RagFlowTool)
    end

    it "excludes disabled tools" do
      agent = create(:agent)
      connector = create(:connector, :sql_database, :enabled)
      sql_query = create(:tools_sql_query, connector:)
      tool = create(:tool, :disabled, toolable: sql_query)
      agent.update!(tool_ids: [tool.id])

      expect(agent.tools).to be_empty
    end

    it "returns empty array when no tools" do
      agent = create(:agent)
      expect(agent.tools).to eq([])
    end

    it "skips tools that fail to build" do
      agent = create(:agent, :with_sql_tool)

      allow(SqlQueryTool).to receive(:for_tool).and_raise(StandardError, "build failed")
      allow(Rails.logger).to receive(:error)

      expect(agent.tools).to be_empty
    end

    it "returns SubagentTool instances for enabled subagents" do
      agent = create(:agent)
      subagent = create(:agent, :enabled)
      agent.update!(subagent_ids: [subagent.id])

      tools = agent.tools
      expect(tools).to be_an(Array)
      expect(tools.size).to eq(1)
      expect(tools.first).to be_a(SubagentTool)
    end

    it "prioritizes designer subagent tools ahead of runtime tools for Agent Alpha" do
      agent = create(:agent, builtin: true, builtin_key: "agent_alpha", selectable: false)
      subagent = create(:agent, :enabled)
      agent.update!(runtime_tool_keys: ["resources.list_resources"], subagent_ids: [subagent.id])

      runtime_tool = instance_double(RubyLLM::Tool, name: "list_resources")
      subagent_tool = instance_double(SubagentTool, name: "ask_agent_mission_designer")

      allow(BuiltinTools::Registry).to receive(:build).and_return(runtime_tool)
      allow(SubagentTool).to receive(:for_agent).and_return(subagent_tool)

      expect(agent.tools.map(&:name).take(2)).to eq(["ask_agent_mission_designer", "list_resources"])
    end

    it "excludes disabled subagents" do
      agent = create(:agent)
      subagent = create(:agent, :disabled)
      agent.update!(subagent_ids: [subagent.id])

      expect(agent.tools).to be_empty
    end

    it "handles errors building tools gracefully" do
      agent = create(:agent, :with_sql_tool)

      allow(SqlQueryTool).to receive(:for_tool).and_raise(StandardError.new("boom"))
      allow(Rails.logger).to receive(:error)

      expect(agent.tools).to eq([])
    end

    it "handles errors building subagent tools gracefully" do
      agent = create(:agent)
      subagent = create(:agent, :enabled)
      agent.update!(subagent_ids: [subagent.id])

      allow(SubagentTool).to receive(:for_agent).and_raise(StandardError.new("boom"))
      allow(Rails.logger).to receive(:error)

      expect(agent.tools).to eq([])
    end

    it "handles errors building runtime tools gracefully" do
      agent = create(:agent)
      agent.update!(runtime_tool_keys: ["mission_designer.validate_flow"])

      allow(BuiltinTools::Registry).to receive(:build).and_raise(StandardError, "boom")
      allow(BuiltinTools::Registrations).to receive(:register_all!)
      allow(Rails.logger).to receive(:error)

      expect(agent.tools).to eq([])
      expect(Rails.logger).to have_received(:error).with(/Failed to build runtime tool/)
    end

    it "refreshes builtin registrations and retries runtime tool builds once" do
      agent = create(:agent)
      agent.update!(runtime_tool_keys: ["agent_designer.read_agent_chat"])

      recovered_tool = instance_double(RubyLLM::Tool, name: "read_agent_chat")
      build_attempts = 0
      allow(BuiltinTools::Registrations).to receive(:register_all!)
      allow(BuiltinTools::Registry).to receive(:build)
        .with("agent_designer.read_agent_chat", agent:, parent_chat: nil) do
          build_attempts += 1
          raise KeyError, "missing definition" if build_attempts == 1

          recovered_tool
        end

      expect(agent.tools).to include(recovered_tool)
      expect(BuiltinTools::Registrations).to have_received(:register_all!)
    end
  end

  describe "#ask" do
    let(:agent) { create(:agent, model_id: "gpt-4.1", temperature: 0.5, instructions: "Be helpful") }

    before do
      create(:model, model_id: "gpt-4.1", provider: "openai")
      # Stub LLM calls on the AR Chat that build_chat creates
      allow_any_instance_of(Chat).to receive(:with_model) do |chat, model_name, **_opts| # rubocop:disable RSpec/AnyInstance
        chat.assume_model_exists = true
        chat.model = model_name if model_name.present?
        chat.provider = "openai"
        chat.save! if chat.new_record?
        chat
      end
      allow_any_instance_of(Chat).to receive(:with_temperature).and_return(nil) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Chat).to receive(:with_instructions).and_return(nil) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Chat).to receive(:with_tools).and_return(nil) # rubocop:disable RSpec/AnyInstance
    end

    it "creates a persisted chat and asks the question" do
      allow_any_instance_of(Chat).to receive(:ask).with("Hello").and_return("Hi there!") # rubocop:disable RSpec/AnyInstance

      result = agent.ask("Hello")
      expect(result).to eq("Hi there!")
    end

    it "creates a child chat linked to parent_chat when provided" do
      parent = create(:chat, agent:)
      allow_any_instance_of(Chat).to receive(:ask).and_return("response") # rubocop:disable RSpec/AnyInstance

      agent.ask("Hello", parent_chat: parent)

      child = Chat.where(parent_chat: parent).last
      expect(child).to be_present
      expect(child.agent).to eq(agent)
    end

    it "skips instructions when blank" do
      agent.update!(instructions: nil)
      allow_any_instance_of(Chat).to receive(:ask).and_return("Hello!") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Chat).not_to receive(:with_instructions) # rubocop:disable RSpec/AnyInstance

      agent.ask("Hi")
    end

    it "uses explicit execution_context when provided" do
      allow_any_instance_of(Chat).to receive(:ask).and_return("response") # rubocop:disable RSpec/AnyInstance

      agent.ask("Hello", execution_context: :test)

      chat = Chat.where(agent:).last
      expect(chat.execution_context).to eq("test")
    end

    it "includes tools when available" do
      agent_with_tool = create(:agent, :with_sql_tool, model_id: "gpt-4.1", temperature: 0.5, instructions: nil)
      allow_any_instance_of(Chat).to receive(:ask).and_return("response") # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Chat).to receive(:with_tools) # rubocop:disable RSpec/AnyInstance

      agent_with_tool.ask("test")
    end

    it "raises when a runtime-configured agent has no runtime model" do
      runtime_agent = create(:agent, llm_connector: nil, model_id: nil, llm_config_source: "runtime")

      expect { runtime_agent.ask("Hello") }
        .to raise_error(/requires runtime LLM configuration/)
    end
  end

  describe "chat configuration branches" do
    def ui_runtime_context
      {
        ui_context: {
          page: {
            name: "Mission details",
            controller: "admin/missions",
            action: "designer",
            path: "/admin/missions/1/designer",
          },
          current_object: {
            type: "Mission",
            label: "Policy Mission",
            id: 1,
          },
          operation: { name: "Default", slug: "default" },
          references: [],
          reference_trigger: "#",
        },
      }
    end

    def stub_shared_chat_options(agent, chat, model_record)
      allow(chat).to receive(:context=)
      allow(chat).to receive(:with_model)
      allow(agent).to receive_messages(
        resolve_runtime_configuration: {
          model_id: model_record.model_id,
          model_record:,
          temperature: 0.4,
          context: nil,
          thinking_effort: agent.thinking_effort,
          thinking_budget: agent.thinking_budget,
          custom_params: agent.custom_llm_params,
        },
        build_full_instructions: "",
        tools: [],
      )
      allow(Chat).to receive(:create!).and_return(chat)
      allow(Llm::ChatOptions).to receive(:apply_to_chat)
    end

    def stub_runtime_configuration(agent, model_record)
      allow(agent).to receive_messages(
        resolve_runtime_configuration: {
          model_id: model_record.model_id,
          model_record:,
          temperature: nil,
          context: nil,
        },
        tools: [],
      )
      allow(Llm::ChatOptions).to receive(:apply_to_chat)
    end

    def llm_system_messages(chat)
      chat.to_llm.messages.select { |message| message.role == :system }.map(&:content)
    end

    it "builds chats without loading a model record when no model id is resolved" do
      agent = create(:agent)
      chat = build(:chat, agent:, model: nil)

      allow(agent).to receive(:resolve_runtime_configuration).and_return({ model_id: nil, temperature: nil })
      allow(agent).to receive(:configure_chat)
      allow(Model).to receive(:find_by)
      allow(Chat).to receive(:create!).and_return(chat)

      result = agent.build_chat

      expect(result).to eq(chat)
      expect(Model).not_to have_received(:find_by)
    end

    it "skips context, model, and temperature updates when they are absent" do
      agent = create(:agent)
      chat = instance_spy(Chat)
      allow(agent).to receive_messages(resolve_runtime_configuration: { model_id: nil, temperature: nil },
                                       build_full_instructions: "", tools: [],)

      agent.configure_chat(chat)

      expect(chat).not_to have_received(:context=)
      expect(chat).not_to have_received(:with_model)
      expect(chat).not_to have_received(:with_temperature)
    end

    it "routes temperature, thinking, and custom params through shared chat options" do
      model_record = create(:model, model_id: "gpt-4.1", provider: "openai",
                                    capabilities: ["temperature", "reasoning"],)
      agent = create(:agent, model_id: model_record.model_id, thinking_effort: "high", thinking_budget: 256)
      agent.custom_llm_params = '{"top_p":0.9}'

      chat = instance_double(Chat)
      stub_shared_chat_options(agent, chat, model_record)

      agent.build_chat

      expect(Llm::ChatOptions).to have_received(:apply_to_chat).with(
        chat:,
        model_id: model_record.model_id,
        model_record:,
        tools_present: false,
        temperature: 0.4,
        thinking_effort: "high",
        thinking_budget: 256,
        custom_params: { "top_p" => 0.9 },
      )
    end

    it "overrides thinking effort from chat runtime context" do
      model_record = create(:model, model_id: "gpt-4.1", provider: "openai",
                                    capabilities: ["temperature", "reasoning"],)
      agent = create(:agent, model_id: model_record.model_id, thinking_effort: "high", thinking_budget: 256)
      chat = instance_spy(Chat)
      allow(agent).to receive_messages(build_full_instructions: "", tools: [])
      allow(Llm::ChatOptions).to receive(:apply_to_chat)

      agent.configure_chat(chat, runtime_context: { llm_config: { thinking_effort: "low" } })

      expect(Llm::ChatOptions).to have_received(:apply_to_chat).with(
        hash_including(thinking_effort: "low", thinking_budget: nil),
      )
    end

    it "resets thinking to model default from chat runtime context" do
      agent = create(:agent, thinking_effort: "high", thinking_budget: 256)

      expect(agent.send(:runtime_llm_overrides, "llm_config" => { "thinking_effort" => nil })).to eq(
        thinking_effort: nil,
        thinking_budget: nil,
      )
      expect(agent.send(:runtime_llm_overrides, llm_config: {})).to eq({})
      expect(agent.send(:runtime_llm_overrides, nil)).to eq({})
      expect(agent.send(:runtime_llm_overrides, Object.new)).to eq({})
      expect { agent.send(:runtime_llm_overrides, llm_config: { thinking_effort: "maximum" }) }
        .to raise_error(ArgumentError, "Thinking effort is invalid")
    end

    it "keeps agent instructions when runtime UI context is injected", :aggregate_failures do
      model_record = create(:model, model_id: "gpt-4.1", provider: "openai")
      agent = create(:agent, model_id: model_record.model_id, instructions: "Be helpful")
      chat = create(:chat, agent:, model: model_record)
      runtime_instructions = Agents::RuntimeContextInstructions.new(ui_runtime_context).build
      original_openai_api_key = RubyLLM.config.openai_api_key

      stub_runtime_configuration(agent, model_record)
      RubyLLM.configure { |config| config.openai_api_key = "test-key" }

      agent.configure_chat(chat, runtime_context: ui_runtime_context)

      expect(chat.messages.where(role: :system).pluck(:content)).to eq(["Be helpful"])
      expect(llm_system_messages(chat)).to eq(["Be helpful", runtime_instructions])
    ensure
      RubyLLM.configure { |config| config.openai_api_key = original_openai_api_key }
    end

    # rubocop:disable RSpec/ExampleLength
    it "uses the system preference connector when attaching routed models" do
      model_record = create(:model, model_id: "gpt-4.1", provider: "openai")
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      create(:system_preference, tenant:, llm_connector: connector, model_id: model_record.model_id)
      agent = create(
        :agent,
        operation: create(:operation, tenant:),
        llm_connector: nil,
        model_id: model_record.model_id,
      )
      agent.llm_config_source = "system_preference"
      chat = instance_double(Chat, with_model: nil, configure_model_routing!: nil)
      allow(chat).to receive(:context=)

      allow(agent).to receive_messages(
        resolve_runtime_configuration: {
          model_id: model_record.model_id,
          model_record:,
          temperature: nil,
          context: nil,
          thinking_effort: nil,
          thinking_budget: nil,
          custom_params: {},
          model_routing_config: { "strategy" => "fallback" },
          connector: nil,
        },
        build_full_instructions: "",
        tools: [],
      )
      allow(Llm::ChatOptions).to receive(:apply_to_chat)

      agent.configure_chat(chat)

      expect(chat).to have_received(:configure_model_routing!).with(hash_including(primary_connector: connector))
    end
    # rubocop:enable RSpec/ExampleLength

    it "falls back to the agent connector when no runtime connector is present" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      agent = create(:agent, operation: create(:operation, tenant:), llm_connector: connector)

      expect(agent.send(:resolved_runtime_connector, { connector: nil })).to eq(connector)
    end

    it "prefers the runtime connector when one is provided" do
      tenant = create(:tenant)
      agent_connector = create(:connector, :llm_provider, :enabled, tenant:)
      runtime_connector = create(:connector, :llm_provider, :enabled, tenant:)
      agent = create(:agent, operation: create(:operation, tenant:), llm_connector: agent_connector)

      expect(agent.send(:resolved_runtime_connector, { connector: runtime_connector })).to eq(runtime_connector)
    end

    it "falls back to the agent connector when system preferences are unavailable" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      agent = create(
        :agent,
        operation: create(:operation, tenant:),
        llm_connector: connector,
        llm_config_source: "system_preference",
      )
      allow(SystemPreference).to receive(:current).with(tenant:).and_return(nil)

      expect(agent.send(:resolved_runtime_connector, { connector: nil })).to eq(connector)
    end

    it "falls back to the agent connector when system preferences are not configured" do
      tenant = create(:tenant)
      connector = create(:connector, :llm_provider, :enabled, tenant:)
      create(:system_preference, tenant:)
      agent = create(
        :agent,
        operation: create(:operation, tenant:),
        llm_connector: connector,
        llm_config_source: "system_preference",
      )

      expect(agent.send(:resolved_runtime_connector, { connector: nil })).to eq(connector)
    end
  end

  describe "model routing config helpers" do
    it "returns the default config when stored routing data is malformed" do
      agent = build(:agent)
      agent.configuration["model_routing_config"] = '["bad"]'

      expect(agent.model_routing_config).to eq(Llm::ModelRoutingConfig.default)
    end

    it "formats non-string routing config JSON inputs for the edit form" do
      agent = build(:agent)

      expect(agent.send(:model_routing_config_json_input, nil)).to eq("")
      expect(agent.send(:model_routing_config_json_input, { "strategy" => "fallback" })).to include('"strategy"')
    end

    it "falls back to to_s when formatting routing config JSON fails" do
      agent = build(:agent)
      value = Object.new
      value.define_singleton_method(:to_json) { |_state = nil| raise JSON::GeneratorError, "boom" }

      expect(agent.send(:model_routing_config_json_input, value)).to eq(value.to_s)
    end

    it "returns the cached routing JSON input when present" do
      agent = build(:agent)

      agent.model_routing_config = '{"strategy":"fallback"'

      expect(agent.model_routing_config_json).to eq('{"strategy":"fallback"')
    end

    it "formats stored non-default routing config when no cached input is set" do
      agent = build(:agent)
      agent.configuration["model_routing_config"] = {
        "strategy" => "fallback",
        "fallback_models" => [{ "connector_id" => 1, "model_id" => "gpt-4.1-mini" }],
      }

      expect(agent.model_routing_config_json).to include('"strategy": "fallback"')
    end
  end

  describe "#should_generate_new_friendly_id?" do
    it "returns true when name changes" do
      agent = create(:agent, name: "Original Name")
      agent.name = "New Name"
      expect(agent.should_generate_new_friendly_id?).to be(true)
    end

    it "returns true when slug is blank" do
      agent = build(:agent)
      agent.slug = nil
      expect(agent.should_generate_new_friendly_id?).to be(true)
    end

    it "returns false when name unchanged and slug present" do
      agent = create(:agent)
      agent.reload
      expect(agent.should_generate_new_friendly_id?).to be(false)
    end
  end

  describe "#parent_agents" do
    it "returns agents that reference this agent as a subagent" do
      parent = create(:agent)
      child = create(:agent)
      parent.update!(subagent_ids: [child.id])

      expect(child.parent_agents).to include(parent)
    end
  end

  describe "subagent cycle detection" do
    it "rejects subagent references that form a cycle" do
      agent_a = create(:agent)
      agent_b = create(:agent)
      agent_a.update!(subagent_ids: [agent_b.id])

      agent_b.subagent_ids = [agent_a.id]
      expect(agent_b).not_to be_valid
      expect(agent_b.errors[:subagent_ids]).to include("would create a cyclic reference")
    end

    it "rejects self-referencing subagent" do
      agent = create(:agent)
      agent.subagent_ids = [agent.id]
      expect(agent).not_to be_valid
      expect(agent.errors[:subagent_ids]).to include("cannot include the agent itself")
    end

    it "skips cycle check for unpersisted agents" do
      subagent = create(:agent)
      agent = build(:agent)
      agent.subagent_ids = [subagent.id]
      expect(agent).to be_valid
    end

    it "detects cycles through diamond-shaped subagent graphs" do
      # A -> B, A -> C, B -> D, C -> D — then D -> A creates a cycle
      # The BFS from D will visit both B and C, and B's children include D (already visited)
      agent_a = create(:agent)
      agent_b = create(:agent)
      agent_c = create(:agent)
      agent_d = create(:agent)

      agent_a.update!(subagent_ids: [agent_b.id, agent_c.id])
      agent_b.update!(subagent_ids: [agent_d.id])
      agent_c.update!(subagent_ids: [agent_d.id])

      agent_d.subagent_ids = [agent_a.id]
      expect(agent_d).not_to be_valid
      expect(agent_d.errors[:subagent_ids]).to include("would create a cyclic reference")
    end

    it "treats missing stored subagent configuration as an empty child list" do
      agent = create(:agent)
      missing_id = agent.id + 10_000

      allow(described_class).to receive(:where).and_call_original
      relation = instance_double(ActiveRecord::Relation, pick: nil)
      allow(described_class).to receive(:where).with(id: missing_id).and_return(relation)
      agent.subagent_ids = [missing_id]

      expect(agent).to be_valid
    end

    it "skips nodes that were already visited during cycle detection" do
      agent = create(:agent)
      first_missing_id = agent.id + 10_001
      second_missing_id = agent.id + 10_002

      allow(described_class).to receive(:where).and_call_original
      relation_for_two = instance_double(ActiveRecord::Relation)
      relation_for_three = instance_double(ActiveRecord::Relation)
      allow(described_class).to receive(:where).with(id: first_missing_id).and_return(relation_for_two)
      allow(described_class).to receive(:where).with(id: second_missing_id).and_return(relation_for_three)
      allow(relation_for_two).to receive(:pick).with(:configuration).and_return(
        { "subagent_ids" => [second_missing_id, second_missing_id] },
      )
      allow(relation_for_three).to receive(:pick).with(:configuration).and_return({ "subagent_ids" => [] })
      agent.subagent_ids = [first_missing_id]

      expect(agent).to be_valid
    end
  end

  describe "amoeba cloning" do
    it "deep clones capabilities and configuration" do
      agent = create(:agent)
      agent.set_capability_config("chat_title_generator", {
                                    "max_length" => 30,
                                    "max_turns" => 3,
                                    "llm_config_source" => "inherit",
                                    "temperature" => 0.7,
                                  }, enabled: true,)
      agent.save!

      clone = agent.amoeba_dup
      clone.name = "#{agent.name} Copy"
      clone.save!

      expect(clone.capability_enabled?(:chat_title_generator)).to be(true)
      original_cap = agent.capability(:chat_title_generator)
      cloned_cap = clone.capability(:chat_title_generator)
      expect(cloned_cap.max_length).to eq(original_cap.max_length)
    end

    it "builds capability configurators that do not expose _agent_record=" do
      stub_const("DummyCapabilityNoAgentRecord", Class.new do
        def initialize(*) = nil
      end,)
      allow(CapabilityPlugin).to receive(:resolve).and_call_original
      allow(CapabilityPlugin).to receive(:resolve)
        .with("dummy_no_agent_record")
        .and_return(DummyCapabilityNoAgentRecord)

      agent = build(:agent)

      expect(agent.capability(:dummy_no_agent_record)).to be_a(DummyCapabilityNoAgentRecord)
    end

    it "builds capability entries that do not expose _agent_record=" do
      stub_const("DummyCapabilityEntryNoAgentRecord", Class.new do
        def initialize(*) = nil
      end,)
      allow(CapabilityPlugin).to receive(:resolve).and_call_original
      allow(CapabilityPlugin).to receive(:resolve)
        .with("dummy_entry_no_agent_record")
        .and_return(DummyCapabilityEntryNoAgentRecord)

      agent = build(:agent)
      entry = HasCapabilities::CapabilityEntry.new("dummy_entry_no_agent_record", true, {}, agent)

      expect(entry.configurator).to be_a(DummyCapabilityEntryNoAgentRecord)
    end
  end

  describe "#build_tool_for (private)" do
    it "returns nil for unknown toolable_type" do
      agent = create(:agent)
      tool_record = instance_double(Tool, toolable_type: "Tools::Unknown", toolable: nil, name: "test")

      result = agent.send(:build_tool_for, tool_record)
      expect(result).to be_nil
    end

    it "uses tool_type when tool_record responds to it" do
      agent = create(:agent)
      tool_record = instance_double(Tool, tool_type: "sql_query", name: "test")
      allow(tool_record).to receive(:respond_to?).with(:tool_type).and_return(true)
      allow(SqlQueryTool).to receive(:for_tool).and_return(double)
      agent.send(:build_tool_for, tool_record)
      expect(SqlQueryTool).to have_received(:for_tool)
    end

    it "builds a MissionToolAdapter for mission_tool type" do
      agent = create(:agent)
      mission_tool_record = create(:tool, :mission_tool)
      allow(MissionToolAdapter).to receive(:for_tool).and_return(instance_double(MissionToolAdapter))
      agent.send(:build_tool_for, mission_tool_record)
      expect(MissionToolAdapter).to have_received(:for_tool).with(mission_tool_record)
    end

    it "falls back to toolable_type when tool_type is not available" do
      agent = create(:agent)
      record = double("ToolRecord", name: "test") # rubocop:disable RSpec/VerifiedDoubles
      allow(record).to receive(:respond_to?).with(:tool_type).and_return(false)
      allow(record).to receive(:respond_to?).with(:toolable_type).and_return(true)
      allow(record).to receive(:toolable_type).and_return("Tools::Unknown")

      result = agent.send(:build_tool_for, record)
      expect(result).to be_nil
    end

    it "returns nil when the record exposes neither tool_type nor toolable_type" do
      agent = create(:agent)
      record = double("ToolRecord", name: "test") # rubocop:disable RSpec/VerifiedDoubles
      allow(record).to receive(:respond_to?).with(:tool_type).and_return(false)
      allow(record).to receive(:respond_to?).with(:toolable_type).and_return(false)

      expect(agent.send(:build_tool_for, record)).to be_nil
    end
  end

  describe "#build_full_instructions" do
    it "returns only instructions when no capabilities" do
      agent = create(:agent, instructions: "Be helpful")
      expect(agent.build_full_instructions).to eq("Be helpful")
    end

    it "returns empty string when no instructions and no capability additions" do
      agent = create(:agent, instructions: nil)
      expect(agent.build_full_instructions).to eq("")
    end
  end

  describe "llm_connector validation" do
    it "allows an LLM provider connector" do
      connector = create(:connector, :llm_provider, :enabled)
      agent = build(:agent, llm_connector: connector)
      expect(agent).to be_valid
    end

    it "rejects a non-LLM connector" do
      connector = create(:connector, :sql_database)
      agent = build(:agent, llm_connector: connector)
      expect(agent).not_to be_valid
      expect(agent.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "rejects an orphaned llm_connector_id (connector deleted)" do
      agent = build(:agent, llm_connector: nil)
      agent.llm_connector_id = 999_999_999
      expect(agent).not_to be_valid
      expect(agent.errors[:llm_connector_id]).to include("must be an LLM Provider connector")
    end

    it "allows nil llm_connector (column is nullable)" do
      agent = build(:agent)
      agent.llm_connector = nil
      expect(agent).to be_valid
    end
  end

  describe "#resolve_llm_context" do
    it "falls back to connector lookup when tenant access is unavailable" do
      connector = create(:connector, :llm_provider, :enabled)
      agent = build(:agent, llm_connector: connector)

      allow(agent).to receive(:respond_to?).and_call_original
      allow(agent).to receive(:respond_to?).with(:tenant).and_return(false)

      expect(agent.llm_connector).to eq(connector)
    end

    it "builds a RubyLLM context from llm_connector" do
      connector = create(:connector, :llm_provider, :enabled)
      agent = build(:agent, llm_connector: connector)

      context = agent.resolve_llm_context
      expect(context).to be_a(RubyLLM::Context)
    end

    it "returns nil when no llm_connector is assigned" do
      agent = build(:agent, llm_connector: nil)

      expect(agent.resolve_llm_context).to be_nil
    end

    it "returns nil when llm_connector_id references a deleted connector" do
      agent = build(:agent, llm_connector: nil)
      agent.llm_connector_id = 999_999

      expect(agent.resolve_llm_context).to be_nil
    end

    it "returns the build_context from the associated connector" do
      connector = create(:connectors_llm_provider, enabled: true)
      agent = build(:agent, llm_connector: connector)

      allow(agent.tenant.connectors).to receive(:find_by).with(id: connector.id).and_return(connector)
      allow(connector).to receive(:build_context).and_return(:ctx)

      expect(agent.resolve_llm_context).to eq(:ctx)
    end

    it "propagates CredentialDecryptionError when credentials cannot be decrypted" do
      connector = create(:connectors_llm_provider, enabled: true)
      agent = build(:agent, llm_connector: connector)

      allow(agent.tenant.connectors).to receive(:find_by).with(id: connector.id).and_return(connector)
      allow(connector).to receive(:build_context)
        .and_raise(Connectors::LlmProvider::CredentialDecryptionError.new(connector.name))

      expect { agent.resolve_llm_context }.to raise_error(
        Connectors::LlmProvider::CredentialDecryptionError,
        /Cannot decrypt credentials/,
      )
    end
  end

  describe "ensure_configuration callback" do
    it "coerces non-Hash configuration to empty Hash before validation" do
      agent = build(:agent)
      agent.configuration = nil
      agent.valid?
      expect(agent.configuration).to eq({})
    end
  end

  describe "llm_connector= setter" do
    it "sets nil llm_connector_id when connector is nil" do
      agent = build(:agent)
      agent.llm_connector = nil
      expect(agent.llm_connector_id).to be_nil
    end
  end

  describe "private runtime configuration helpers" do
    def configured_preference_double(connector:)
      instance_double(
        SystemPreference,
        configured?: true,
        llm_connector: connector,
        model_id: "gpt-4.1",
        resolve_llm_context: :ctx,
        temperature: 0.2,
        llm_runtime_settings: {
          thinking_effort: "high",
          thinking_budget: 2048,
          custom_params: { "top_p" => 0.8 },
          model_routing_config: Llm::ModelRoutingConfig.default,
        },
      )
    end

    it "falls back to the agent model when no runtime override is provided" do
      agent = create(:agent, model_id: "gpt-4.1", llm_config_source: "agent")

      config = agent.send(
        :resolve_runtime_configuration,
        model_id: nil,
        temperature: Agent::UNSET,
        llm_context: Agent::UNSET,
      )

      expect(config[:model_id]).to eq("gpt-4.1")
    end

    it "uses configured system preferences when runtime values are unset" do
      agent = build(:agent, llm_connector: nil, model_id: nil, llm_config_source: "system_preference")
      connector = instance_double(Connector)
      model_record = instance_double(Model)

      allow(SystemPreference).to receive(:current).and_return(configured_preference_double(connector:))
      allow(Llm::ChatOptions).to receive(:resolve_model).with("gpt-4.1").and_return(model_record)

      config = agent.send(
        :resolve_runtime_configuration,
        model_id: nil,
        temperature: Agent::UNSET,
        llm_context: Agent::UNSET,
      )

      expect(config).to eq(
        model_id: "gpt-4.1",
        model_record:,
        temperature: 0.2,
        context: :ctx,
        connector:,
        thinking_effort: "high",
        thinking_budget: 2048,
        custom_params: { "top_p" => 0.8 },
        model_routing_config: Llm::ModelRoutingConfig.default,
      )
    end

    it "raises when system preference configuration is requested without a preference" do
      agent = build(:agent, llm_connector: nil, model_id: nil, llm_config_source: "system_preference")
      allow(SystemPreference).to receive(:current).and_return(nil)

      expect do
        agent.send(
          :resolve_runtime_configuration,
          model_id: nil,
          temperature: Agent::UNSET,
          llm_context: Agent::UNSET,
        )
      end.to raise_error(/Default model is not configured/)
    end

    it "raises when default runtime context is requested without a configured preference" do
      agent = build(:agent, llm_connector: nil, model_id: nil, llm_config_source: "system_preference")

      expect { agent.send(:default_runtime_context, nil) }
        .to raise_error(/Default model is not configured/)
    end
  end
end
