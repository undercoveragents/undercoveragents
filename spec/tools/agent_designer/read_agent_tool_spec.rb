# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::ReadAgentTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:expected_read_agent_fragments) do
    [
      "## Agent",
      "Agent Builder",
      "## Assigned Tools",
      "Agent Helper",
      "## Built-in Runtime Tools",
      "records.manage_record",
      "## Sub-Agents",
      "Subagent Helper",
      "## Skill Catalogs",
      "Ops Guide",
      "## Capabilities",
      "chat_title_generator",
      "manage_capability",
      "## Input Schema",
      "`task`",
      "## Model Routing",
      '"strategy": "fallback"',
      "## Custom LLM Params",
      '"top_p": 0.2',
      "## Instructions",
      "Use {{task}} to help.",
      "## Editable Attribute Keys",
      "`assigned_tool_ids`",
      "manage_record(action: \"clone\", resource: \"agent\"",
      "`model_routing_config`",
      "Capability configuration goes through `manage_capability`",
    ]
  end
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation:,
    )
  end

  def create_configured_agent(operation:, helper_tool:, helper_subagent:, skill_catalog:, llm_connector:)
    agent = create(
      :agent,
      operation:,
      name: "Agent Builder",
      description: "Builds internal helpers",
      instructions: "Use {{task}} to help.",
      model_id: "gpt-4.1",
      agent_type: "code_assistant",
    )
    agent.assigned_tool_ids = [helper_tool.id]
    agent.subagent_ids = [helper_subagent.id]
    agent.skill_catalog_ids = [skill_catalog.id]
    agent.input_schema = [{ variable_name: "task", label: "Task", field_type: "string", required: true }]
    agent.custom_llm_params = { "top_p" => 0.2 }
    agent.model_routing_config = fallback_model_routing_config(llm_connector)
    agent.set_capability_config("chat_title_generator", { "max_length" => 30 })
    agent.runtime_tool_keys = ["records.manage_record"]
    agent.save!
    agent
  end

  def fallback_model_routing_config(llm_connector)
    {
      "strategy" => "fallback",
      "fallback_models" => [{ "connector_id" => llm_connector.id, "model_id" => "gpt-4.1-mini" }],
    }
  end

  def build_optional_details_agent(operation:)
    agent = build(
      :agent,
      operation:,
      name: "Builtin Helper",
      description: nil,
      instructions: "",
      thinking_effort: "high",
      thinking_budget: 128,
    )
    agent.llm_connector_id = nil
    agent.model_id = nil
    agent.builtin_key = "agent_designer"
    agent.input_schema = [{
      variable_name: "task",
      label: "Task",
      field_type: "string",
      required: false,
      config: { min: 1 },
    }]
    agent
  end

  def capability_entry(type:, label:, configuration:, respond_to_summary:, summary: nil)
    if respond_to_summary
      Struct.new(:capability_type, :type_label, :configuration, :summary).new(type, label, configuration, summary)
    else
      Struct.new(:capability_type, :type_label, :configuration).new(type, label, configuration)
    end
  end

  describe "#name" do
    it "returns read_agent" do
      expect(described_class.new(runtime_context:).name).to eq("read_agent")
    end
  end

  describe "#execute" do
    it "reads the current agent configuration and editable fields" do
      helper_tool = create(:tool, :mission_tool, :enabled, operation:, name: "Agent Helper")
      helper_subagent = create(:agent, :enabled, operation:, name: "Subagent Helper", model_id: "gpt-4.1")
      skill_catalog = create(:skill_catalog, operation:, name: "Ops Guide")
      llm_connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Primary LLM")
      agent = create_configured_agent(operation:, helper_tool:, helper_subagent:, skill_catalog:, llm_connector:)

      result = described_class.new(runtime_context:, current_agent: agent).execute

      expect(result).to include(*expected_read_agent_fragments)
    end

    it "finds an agent by id inside the current operation" do
      agent = create(:agent, operation:, name: "Scoped Agent", model_id: "gpt-4.1")
      foreign_agent = create(:agent, operation: create(:operation, tenant:), name: "Foreign Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:)

      expect(tool.execute(agent_id: agent.id)).to include("Scoped Agent")
      expect(tool.execute(agent_id: foreign_agent.id)).to eq("Error: Agent '#{foreign_agent.id}' was not found.")
    end

    it "finds an agent by unique name inside the current operation" do
      agent = create(:agent, operation:, name: "Named Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:)

      expect(tool.execute(agent_id: agent.name)).to include("Named Agent")
    end

    it "scopes agent lookup by tenant when no runtime operation is present" do
      visible_agent = create(:agent, operation:, name: "Scoped Tenant Agent", model_id: "gpt-4.1")
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_agent = create(
        :agent,
        operation: foreign_tenant.default_operation,
        name: "Foreign Tenant Agent",
        model_id: "gpt-4.1",
      )
      tool = described_class.new(runtime_context: runtime_context.with(operation: nil))

      expect(tool.execute(agent_id: visible_agent.id)).to include("Scoped Tenant Agent")
      expect(tool.execute(agent_id: foreign_agent.id)).to eq("Error: Agent '#{foreign_agent.id}' was not found.")
    end

    it "asks for an id or slug when a tenant-scoped name is ambiguous" do
      other_operation = create(:operation, tenant:, name: "Another Workspace")
      create(:agent, operation:, name: "Shared Name", model_id: "gpt-4.1")
      create(:agent, operation: other_operation, name: "Shared Name", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context: runtime_context.with(operation: nil))

      expect(tool.execute(agent_id: "Shared Name")).to eq(
        "Error: Multiple agents named 'Shared Name' were found. Pass the numeric ID or slug instead.",
      )
    end

    it "renders builtin, optional model, and input schema details" do
      agent = build_optional_details_agent(operation:)
      tool = described_class.new(runtime_context:)

      expect(tool.send(:summary_section, agent)).to include("- Built-in key: `agent_designer`")
      expect(tool.send(:llm_section, agent)).to include("- Thinking effort: `high`", "- Thinking budget: `128`")
      expect(tool.send(:llm_section, agent)).not_to include("LLM connector ID", "Model ID")
      expect(tool.send(:model_routing_section, agent)).to include("Single route only")
      expect(tool.send(:input_schema_section, agent)).to include("(string, optional) config={\"min\":1}")
    end

    it "renders capability summaries and config guidance" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      agent.set_capability_config("chat_title_generator", { "max_length" => 42, "max_turns" => 2 })
      agent.save!
      tool = described_class.new(runtime_context:)

      result = tool.send(:capabilities_section, agent)

      expect(result).to include("`chat_title_generator`", "max 42 chars", 'config: `{"max_length":42,"max_turns":2}`')
      expect(result).to include("Use `manage_capability` to add, update, or remove capability configs.")
    end

    it "renders capabilities without summaries or config payloads" do
      agent = create(:agent, operation:, name: "Capability Agent", model_id: "gpt-4.1")
      no_summary = capability_entry(
        type: "basic_capability",
        label: "Basic Capability",
        configuration: {},
        respond_to_summary: false,
      )
      blank_summary = capability_entry(
        type: "blank_capability",
        label: "Blank Capability",
        configuration: nil,
        respond_to_summary: true,
        summary: " ",
      )
      allow(agent).to receive(:configured_capabilities).and_return([no_summary, blank_summary])
      tool = described_class.new(runtime_context:)

      result = tool.send(:capabilities_section, agent)

      expect(result).to include("`basic_capability` — Basic Capability")
      expect(result).to include("`blank_capability` — Blank Capability")
      expect(result).not_to include("config:")
    end

    it "rescues unexpected errors while rendering" do
      agent = create(:agent, operation:, name: "Explosive Agent", model_id: "gpt-4.1")
      tool = described_class.new(runtime_context:, current_agent: agent)
      allow(tool).to receive(:summary_section).and_raise(StandardError, "boom")

      expect(tool.execute).to eq("Error reading agent: boom")
    end

    it "returns a helpful message when there is no current agent" do
      result = described_class.new(runtime_context:).execute

      expect(result).to eq(
        "No current agent is available. Pass agent_id after creating one or open an agent page first.",
      )
    end
  end

  describe "fallback accessors" do
    around do |example|
      original_tenant = Current.tenant
      Current.tenant = nil
      example.run
      Current.tenant = original_tenant
    end

    it "reads the tenant from runtime context when present" do
      expect(described_class.new(runtime_context:).send(:tenant)).to eq(tenant)
    end

    it "falls back from current agent, Current.tenant, and default tenant" do
      current_agent = build_stubbed(:agent, operation:)
      Current.tenant = tenant

      expect(described_class.new(runtime_context: nil, current_agent:).send(:tenant)).to eq(tenant)
      expect(described_class.new(runtime_context: nil).send(:tenant)).to eq(tenant)

      Current.tenant = nil
      allow(Tenant).to receive(:default_tenant).and_return(tenant)

      expect(described_class.new(runtime_context: nil).send(:tenant)).to eq(tenant)
    end

    it "falls back from current agent to resolve the operation" do
      current_agent = build_stubbed(:agent, operation:)

      expect(described_class.new(runtime_context: nil, current_agent:).send(:operation)).to eq(operation)
      expect(described_class.new(runtime_context: nil).send(:operation)).to be_nil
    end
  end
end
