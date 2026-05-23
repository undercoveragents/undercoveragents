# frozen_string_literal: true

require "rails_helper"

RSpec.describe ListResourcesTool do
  def runtime_context_with_selection(tenant:)
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: {
        "current_object" => {
          "type" => "Skill catalog",
          "id" => 12,
          "label" => "Operations Skills",
        },
        "references" => [
          { "type" => "Mission", "id" => 7, "label" => "Onboarding Flow" },
        ],
      },
      user: nil,
      tenant:,
      operation: tenant.default_operation,
    )
  end

  def build_runtime_context(tenant:, operation:, **kwargs)
    BuiltinTools::RuntimeContext::Context.new(
      agent: kwargs.fetch(:agent, nil),
      chat: kwargs.fetch(:chat, nil),
      mission: kwargs.fetch(:mission, nil),
      ui_context: kwargs.fetch(:ui_context, nil),
      user: kwargs.fetch(:user, nil),
      tenant:,
      operation:,
    )
  end

  let(:generic_description) do
    "Do not use it as a preflight step when another tool or sub-agent can execute the task directly"
  end

  let(:tenant) do
    create(:tenant).tap(&:ensure_core_resources!)
  end
  let(:mission) { create(:mission, operation: tenant.default_operation) }
  let(:tool) { described_class.new(mission) }

  around do |example|
    Current.tenant = tenant
    example.run
  ensure
    Current.reset
  end

  describe "#name" do
    it "returns list_resources" do
      expect(tool.name).to eq("list_resources")
    end
  end

  describe "#description" do
    it "uses the generic description when running for Agent Alpha" do
      agent_alpha = build(:agent, builtin: true, builtin_key: "agent_alpha")
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: agent_alpha,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant:,
        operation: tenant.default_operation,
      )
      alpha_tool = described_class.new(mission, runtime_context:)

      expect(alpha_tool.description).to include(generic_description)
    end

    it "uses the default description outside Agent Alpha" do
      expect(tool.description).to include(generic_description)
    end

    it "uses the generic description when running for Mission Designer" do
      mission_designer = build(:agent, builtin: true, builtin_key: "mission_designer", agent_type: "mission_designer")
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: mission_designer,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant:,
        operation: tenant.default_operation,
      )
      mission_tool = described_class.new(mission, runtime_context:)

      expect(mission_tool.description).to include(generic_description)
    end

    it "uses the same generic description when agent_type provides the match" do
      mission_designer = build(:agent, builtin: true, builtin_key: nil, agent_type: "mission_designer")
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: mission_designer,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant:,
        operation: tenant.default_operation,
      )
      mission_tool = described_class.new(mission, runtime_context:)

      expect(mission_tool.description).to include(generic_description)
    end
  end

  describe "#execute" do
    it "lists resources for Agent Alpha when asked for direct discovery" do
      connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Prod LLM")
      agent_alpha = build(:agent, builtin: true, builtin_key: "agent_alpha", operation: tenant.default_operation)
      user = create(:user, tenant:)
      chat = create(:chat, :application_context, agent: agent_alpha, user:)
      create(:message, :user, chat:, content: "What LLM connectors are available right now?")

      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: agent_alpha,
        chat:,
        mission: nil,
        ui_context: nil,
        user:,
        tenant:,
        operation: tenant.default_operation,
      )

      alpha_tool = described_class.new(mission, runtime_context:, current_agent: agent_alpha)
      result = alpha_tool.execute(kind: "llm_connectors")

      expect(result).to include("## LLM Connectors", "Prod LLM", "`#{connector.id}`")
    end

    it "lists available kinds when kind and kinds are omitted" do
      allow(tool).to receive(:plugin_defined_kinds).and_return([])

      result = tool.execute

      expect(result).to include("Available resource kinds:")
      expect(result).to include(
        "Core: agent_types, capabilities, models, default_models, tool_types, tools, runtime_tools, " \
        "agents, missions, channels, clients, skill_catalogs, skills, rag_flows, connectors, test_suites",
      )
      expect(result).not_to include("Plugin-defined:")
      expect(result).to include("Use connector_id when kind includes \"models\".")
    end

    it "includes the current page object and selected references in the no-arg discovery response" do
      result = described_class.new(nil, runtime_context: runtime_context_with_selection(tenant:)).execute

      expect(result).to include("Current page object: Operations Skills (`12`)")
      expect(result).to include("Selected references: Onboarding Flow (`7`)")
    end

    it "summarizes label-only page objects and references without identifiers" do
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: {
          "current_object" => { "label" => "Operations Skills" },
          "references" => [{ "label" => "Onboarding Flow" }],
        },
        user: nil,
        tenant:,
        operation: tenant.default_operation,
      )

      result = described_class.new(nil, runtime_context:).execute

      expect(result).to include("Current page object: Operations Skills")
      expect(result).to include("Selected references: Onboarding Flow")
    end

    it "ignores invalid selected references in the no-arg discovery response" do
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: { "references" => ["invalid-reference"] },
        user: nil,
        tenant:,
        operation: tenant.default_operation,
      )

      expect(described_class.new(nil, runtime_context:).execute).not_to include("Selected references:")
    end

    it "includes plugin-defined kinds in the no-arg discovery response" do
      allow(tool).to receive(:plugin_defined_kinds).and_return(["custom_connectors"])

      expect(tool.execute).to include("Plugin-defined: custom_connectors")
    end

    it "rejects unknown kinds" do
      expect(tool.execute(kind: "bogus")).to include("Unknown kind")
    end

    it "lists multiple resource kinds in one call" do
      connector = create(:connector, :llm_provider, :enabled, name: "Prod LLM")
      tool_record = create(:tool, :mission_tool, :enabled, operation: mission.operation, name: "Mission Helper")

      result = tool.execute(kinds: ["llm_connectors", "tools"])

      expect(result).to include("## LLM Connectors", "Prod LLM", "`#{connector.id}`")
      expect(result).to include("## Tools", "Mission Helper", "`#{tool_record.id}`")
    end

    it "includes valid sections even when one requested kind is invalid" do
      connector = create(:connector, :llm_provider, :enabled, name: "Prod LLM")

      result = tool.execute(kinds: ["bogus", "llm_connectors"])

      expect(result).to include("Unknown kind: 'bogus'")
      expect(result).to include("## LLM Connectors", "Prod LLM", "`#{connector.id}`")
    end

    it "handles unexpected errors" do
      allow(ConnectorPlugin).to receive(:all_types).and_raise(StandardError, "boom")
      expect(tool.execute(kind: "llm_connectors")).to include("Error listing resources", "boom")
    end

    it "ignores connector registry entries without list_resources metadata" do
      connector_types = [
        { key: "broken_connector", label: "Broken Connector", description: "" },
      ]

      allow(ConnectorPlugin).to receive(:all_types).and_return(connector_types)
      allow(ConnectorPlugin).to receive(:resolve).with("broken_connector").and_return(Class.new)

      expect(tool.execute).to include("Available resource kinds:")
    end

    it "falls back to the registry label when a connector kind omits a custom title" do
      fallback_connector_class = Class.new do
        def self.list_resources_kind = "custom_connectors"
      end

      connector_types = [
        { key: "custom_connector", label: "Custom Connector", description: "" },
      ]

      allow(ConnectorPlugin).to receive(:all_types).and_return(connector_types)
      allow(ConnectorPlugin).to receive(:resolve).with("custom_connector").and_return(fallback_connector_class)

      expect(tool.send(:connector_resource_definitions)).to eq(
        "custom_connectors" => {
          connector_type: "custom_connector",
          title: "Custom Connectors",
        },
      )
    end

    it "skips connector registry entries that no longer resolve to a loaded class" do
      connector_types = [
        { key: "missing_connector", label: "Missing Connector", description: "" },
      ]

      allow(ConnectorPlugin).to receive(:all_types).and_return(connector_types)
      allow(ConnectorPlugin).to receive(:resolve)
        .with("missing_connector")
        .and_raise(NameError, "uninitialized constant Connectors::SpecConfig")

      expect(tool.send(:connector_resource_definitions)).to eq({})
    end

    it "normalizes plugin-owned resource definitions and skips malformed entries" do
      custom_tool_class = Class.new do
        def self.tool_designer_resource_kinds
          [Object.new, { "kind" => "custom_resources", "model_name" => "Connector" }]
        end
      end

      tool_types = [
        { key: "custom_tool", label: "Custom Tool", description: "" },
        { key: "missing_tool", label: "Missing Tool", description: "" },
      ]

      allow(ToolPlugin).to receive(:all_types).and_return(tool_types)
      allow(ToolPlugin).to receive(:resolve).with("custom_tool").and_return(custom_tool_class)
      allow(ToolPlugin).to receive(:resolve).with("missing_tool").and_return(nil)

      expect(tool.send(:registered_resource_definitions)).to eq(
        "custom_resources" => {
          "kind" => "custom_resources",
          "model_name" => "Connector",
          "title" => "Custom Resources",
          "scope" => "operation_owned",
        },
      )
    end

    it "skips tool registry entries that no longer resolve to a loaded class" do
      tool_types = [
        { key: "missing_tool", label: "Missing Tool", description: "" },
      ]

      allow(ToolPlugin).to receive(:all_types).and_return(tool_types)
      allow(ToolPlugin).to receive(:resolve).with("missing_tool").and_raise(NameError, "uninitialized constant Tools::SpecConfig")

      expect(tool.send(:registered_resource_definitions)).to eq({})
    end

    it "preserves explicit resource titles and scopes during normalization" do
      definition = tool.send(
        :normalize_resource_definition,
        {
          "kind" => "custom_resources",
          "model_name" => "Connector",
          "title" => "Explicit Resources",
          "scope" => "tenant_owned",
        },
      )

      expect(definition).to eq(
        "kind" => "custom_resources",
        "model_name" => "Connector",
        "title" => "Explicit Resources",
        "scope" => "tenant_owned",
      )
    end

    it "returns nil for incomplete resource definitions" do
      expect(tool.send(:normalize_resource_definition, { "kind" => "", "model_name" => "Connector" })).to be_nil
      expect(tool.send(:normalize_resource_definition, { "kind" => "custom_resources", "model_name" => "" })).to be_nil
    end

    it "supports tenant-owned and invalid registered resource scopes" do
      visible_connector = create(:connector, :sql_database, :enabled, tenant:, name: "Tenant Connector")
      create(:connector, :sql_database, :enabled, tenant: create(:tenant), name: "Foreign Connector")

      tenant_scope = tool.send(:scoped_registered_records, { "model_name" => "Connector", "scope" => "tenant_owned" })
      invalid_scope = tool.send(:scoped_registered_records, { "model_name" => "Connector", "scope" => "unknown" })

      expect(tenant_scope).to contain_exactly(visible_connector)
      expect(invalid_scope).to be_empty
    end

    it "returns no operation-owned records when tenant or operation metadata is missing" do
      scope_tool = described_class.new
      allow(scope_tool).to receive(:scoped_operation).and_return(nil)

      expect(scope_tool.send(:scope_registered_records_by_operation, Connector.order(:name))).to be_empty

      tenantless_tool = described_class.new
      allow(tenantless_tool).to receive_messages(scoped_operation: nil, tenant: nil)

      expect(tenantless_tool.send(:scope_registered_records_by_operation, RagFlow.order(:name))).to be_empty
    end

    it "renders registered operation-owned resource kinds through the current operation scope" do
      visible_catalog = create(:skill_catalog, operation: mission.operation, name: "Shared Manual")
      create(:skill_catalog, operation: create(:operation, tenant:), name: "Foreign Manual")
      allow(tool).to receive(:registered_resource_definitions).and_return(
        "custom_skill_catalogs" => {
          "model_name" => "SkillCatalog",
          "title" => "Custom Skill Catalogs",
          "scope" => "operation_owned",
        },
      )

      result = tool.execute(kind: "custom_skill_catalogs")

      expect(result).to include("## Custom Skill Catalogs", "Shared Manual", "`#{visible_catalog.id}`")
      expect(result).not_to include("Foreign Manual")
    end

    it "falls back to tenant operation-owned records for registered resource kinds" do
      list_tool = described_class.new
      visible_flow = create(:rag_flow, operation: tenant.default_operation, name: "Tenant Flow")
      other_tenant = create(:tenant).tap(&:ensure_core_resources!)
      create(:rag_flow, operation: other_tenant.default_operation, name: "Foreign Flow")
      allow(list_tool).to receive(:registered_resource_definitions).and_return(
        "custom_rag_flows" => {
          "model_name" => "RagFlow",
          "title" => "Custom RAG Flows",
          "scope" => "operation_owned",
        },
      )

      result = list_tool.execute(kind: "custom_rag_flows")

      expect(result).to include("## Custom RAG Flows", "Tenant Flow", "`#{visible_flow.id}`")
      expect(result).not_to include("Foreign Flow")
    end

    it "reports when a registered resource kind has no records" do
      allow(tool).to receive(:registered_resource_definitions).and_return(
        "custom_skill_catalogs" => {
          "model_name" => "SkillCatalog",
          "title" => "Custom Skill Catalogs",
          "scope" => "operation_owned",
        },
      )

      expect(tool.execute(kind: "custom_skill_catalogs")).to include("No custom skill catalogs available.")
    end

    describe "llm_connectors" do
      it "lists enabled LLM connectors" do
        connector = create(:connector, :llm_provider, :enabled, name: "Prod LLM")
        result = tool.execute(kind: "llm_connectors")
        expect(result).to include("LLM Connectors", "Prod LLM", "`#{connector.id}`")
      end

      it "says when none are configured" do
        expect(tool.execute(kind: "llm_connectors")).to include("No LLM connectors available.")
      end
    end

    describe "default_models" do
      it "reports when none are configured" do
        expect(tool.execute(kind: "default_models")).to include("No default models configured")
      end

      it "lists configured LLM, embedding, and image models" do
        create(:system_preference, :configured, :with_embedding, :with_image)
        result = tool.execute(kind: "default_models")
        expect(result).to include("Default Models", "LLM:", "Embedding:", "Image:")
      end
    end

    describe "tool_types" do
      it "lists tool types and falls back to a generic description when needed" do
        allow(ToolPlugin).to receive(:all_types).and_return(
          [{ key: "custom_tool", label: "Custom Tool", description: nil }],
        )

        result = tool.execute(kind: "tool_types")

        expect(result).to include("## Tool Types", "`custom_tool`", "Custom Tool", "No description.")
      end

      it "reports when no tool types are available" do
        allow(ToolPlugin).to receive(:all_types).and_return([])

        expect(tool.execute(kind: "tool_types")).to include("No tool types available.")
      end
    end

    describe "runtime_tools" do
      it "lists user-assignable built-in runtime tools" do
        BuiltinTools::Registrations.register_all!

        result = tool.execute(kind: "runtime_tools")

        expect(result).to include(
          "## Built-in Runtime Tools",
          "`web.web_search`",
          "`web.web_fetch`",
        )
        expect(result).not_to include("mission_designer.read_flow")
      end

      it "reports when no built-in runtime tools are user-assignable" do
        allow(BuiltinTools::Registry).to receive(:user_assignable_definitions).and_return([])

        expect(tool.execute(kind: "runtime_tools"))
          .to include("No user-assignable built-in runtime tools available.")
      end

      it "lists user-assignable built-in runtime tools without configuration hints" do
        definition = BuiltinTools::Registry::Definition.new(
          key: "demo.runtime",
          name: "Demo Runtime",
          description: "Demo desc",
          visible_in_headquarter: false,
          user_assignable: true,
          configuration_hint: nil,
          runtime_name: nil,
          icon: nil,
          presentation: nil,
          compaction_policy: nil,
          factory: nil,
        )
        allow(BuiltinTools::Registry).to receive(:user_assignable_definitions).and_return([definition])

        result = tool.execute(kind: "runtime_tools")

        expect(result).to include("`demo.runtime` — Demo Runtime — Demo desc")
        expect(result).not_to include("Configuration:")
      end
    end

    describe "models" do
      it "requires a connector id" do
        expect(tool.execute(kind: "models")).to include("Provide connector_id")
      end

      it "reports when the connector cannot be found" do
        expect(tool.execute(kind: "models", connector_id: "999999")).to include("Connector '999999' was not found.")
      end

      it "reports when the connector does not support model listing" do
        connector = create(:connector, :authentication, :enabled, tenant:)

        expect(tool.execute(kind: "models", connector_id: connector.id))
          .to include("Connector '#{connector.id}' does not support model listing.")
      end

      it "reports when the connector does not expose a provider key" do
        connector = create(:connector, :llm_provider, :enabled, tenant:)
        allow(ConnectorLookup).to receive(:find).with(connector.id, tenant:).and_return(connector)
        allow(connector).to receive(:provider).and_return(nil)

        expect(tool.execute(kind: "models", connector_id: connector.id))
          .to include("Connector '#{connector.id}' does not expose a provider key.")
      end

      it "reports when the resolved connector class does not expose model metadata helpers" do
        connector = create(:connector, :llm_provider, :enabled, tenant:)
        allow(ConnectorPlugin).to receive(:resolve).and_call_original
        allow(ConnectorPlugin).to receive(:resolve).with(connector.connector_type).and_return(Class.new)

        expect(tool.execute(kind: "models", connector_id: connector.id))
          .to include("Connector '#{connector.id}' does not support model listing.")
      end

      it "reports when the resolved connector class supports model listing without a provider key helper" do
        connector = create(:connector, :llm_provider, :enabled, tenant:)
        providerless_class = Class.new do
          def self.supports_model_listing? = true
        end
        allow(ConnectorPlugin).to receive(:resolve).and_call_original
        allow(ConnectorPlugin).to receive(:resolve).with(connector.connector_type).and_return(providerless_class)

        expect(tool.execute(kind: "models", connector_id: connector.id))
          .to include("Connector '#{connector.id}' does not expose a provider key.")
      end

      it "reports when the selected connector provider has no models" do
        connector = build_stubbed(:connector, :llm_provider, :enabled, tenant:, name: "No Models LLM")
        allow(ConnectorLookup).to receive(:find).with(connector.id, tenant:).and_return(connector)
        allow(connector).to receive(:provider).and_return("missing-model-provider")

        expect(tool.execute(kind: "models", connector_id: connector.id))
          .to include("No models found for connector `#{connector.id}`.")
      end

      it "lists models for the selected connector provider" do
        connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Prod LLM", provider: "openai")
        create(:model, provider: "openai", model_id: "gpt-4.1", name: "GPT-4.1")
        create(:model, provider: "anthropic", model_id: "claude-3-7", name: "Claude 3.7")

        result = tool.execute(kind: "models", connector_id: connector.id)

        expect(result).to include("## Models for Prod LLM", "`gpt-4.1`", "GPT-4.1")
        expect(result).not_to include("claude-3-7")
      end
    end

    describe "tools" do
      it "lists enabled tools for the current mission operation" do
        tool_record = create(:tool, :mission_tool, :enabled, operation: mission.operation,
                                                             name: "Mission Helper", description: "Does stuff.",)
        create(:tool, :mission_tool, :disabled, operation: mission.operation, name: "Disabled Helper")
        create(:tool, :mission_tool, :enabled, operation: create(:operation), name: "Foreign Helper")

        result = tool.execute(kind: "tools")
        expect(result).to include("Mission Helper", "`#{tool_record.id}`", "Does stuff.")
        expect(result).not_to include("Disabled Helper", "Foreign Helper")
      end

      it "lists tools globally when no mission is provided" do
        tool_record = create(:tool, :mission_tool, :enabled, name: "Global Helper")
        result = described_class.new.execute(kind: "tools")
        expect(result).to include("Global Helper", "`#{tool_record.id}`")
      end

      it "scopes tools by runtime_context operation when no mission is provided" do
        other_operation = create(:operation, tenant:)
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: nil,
          chat: nil,
          mission: nil,
          ui_context: nil,
          user: nil,
          tenant:,
          operation: mission.operation,
        )
        tool_record = create(:tool, :mission_tool, :enabled, operation: mission.operation, name: "Scoped Helper")
        create(:tool, :mission_tool, :enabled, operation: other_operation, name: "Foreign Helper")

        result = described_class.new(nil, runtime_context:).execute(kind: "tools")

        expect(result).to include("Scoped Helper", "`#{tool_record.id}`")
        expect(result).not_to include("Foreign Helper")
      end

      it "uses the ui_context operation instead of the builtin agent headquarter operation" do
        current_agent = create(:agent, :enabled, operation: tenant.headquarter_operation, name: "Agent Alpha")
        tool_record = create(:tool, :mission_tool, :enabled, operation: tenant.default_operation, name: "Scoped Helper")

        runtime_context = BuiltinTools::RuntimeContext.build(
          agent: current_agent,
          ui_context: { "operation" => { "id" => tenant.default_operation.id } },
        )

        result = described_class.new(nil, runtime_context:, current_agent:).execute(kind: "tools")

        expect(result).to include("Scoped Helper", "`#{tool_record.id}`")
      end

      it "says when no tools are available" do
        expect(tool.execute(kind: "tools")).to include("No enabled tools available.")
      end
    end

    describe "agents" do
      it "lists enabled selectable agents for the mission operation" do
        agent = create(:agent, :enabled, operation: mission.operation, name: "Helper")
        result = tool.execute(kind: "agents")
        expect(result).to include("Agents", "Helper", "`#{agent.id}`")
      end

      it "excludes the current agent when provided" do
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: nil,
          chat: nil,
          mission: nil,
          ui_context: nil,
          user: nil,
          tenant:,
          operation: mission.operation,
        )
        current_agent = create(:agent, :enabled, operation: mission.operation, name: "Current Agent")
        helper_agent = create(:agent, :enabled, operation: mission.operation, name: "Helper Agent")

        result = described_class.new(nil, runtime_context:, current_agent:).execute(kind: "agents")

        expect(result).to include("`#{helper_agent.id}`", "Helper Agent")
        expect(result).not_to include("Current Agent")
      end

      it "lists agents globally when no mission is provided" do
        agent = create(:agent, :enabled, name: "Global Helper")
        expect(described_class.new.execute(kind: "agents")).to include("`#{agent.id}`")
      end

      it "scopes agents by runtime_context operation when no mission is provided" do
        other_operation = create(:operation, tenant:)
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: nil,
          chat: nil,
          mission: nil,
          ui_context: nil,
          user: nil,
          tenant:,
          operation: mission.operation,
        )
        agent = create(:agent, :enabled, operation: mission.operation, name: "Scoped Agent")
        create(:agent, :enabled, operation: other_operation, name: "Foreign Agent")

        result = described_class.new(nil, runtime_context:).execute(kind: "agents")

        expect(result).to include("`#{agent.id}`", "Scoped Agent")
        expect(result).not_to include("Foreign Agent")
      end

      it "uses the ui_context operation instead of the builtin agent headquarter operation" do
        current_agent = create(:agent, :enabled, operation: tenant.headquarter_operation, name: "Agent Alpha")
        helper_agent = create(:agent, :enabled, operation: tenant.default_operation, name: "Scoped Agent")

        runtime_context = BuiltinTools::RuntimeContext.build(
          agent: current_agent,
          ui_context: { "operation" => { "id" => tenant.default_operation.id } },
        )

        result = described_class.new(nil, runtime_context:, current_agent:).execute(kind: "agents")

        expect(result).to include("`#{helper_agent.id}`", "Scoped Agent")
      end

      it "falls back to the tenant default operation for builtin application chats without a resolved operation" do
        current_agent = create(
          :agent,
          :enabled,
          builtin: true,
          builtin_key: "agent_alpha",
          operation: tenant.headquarter_operation,
          name: "Agent Alpha",
        )
        helper_agent = create(:agent, :enabled, operation: tenant.default_operation, name: "Scoped Agent")
        chat = create(:chat, :application_context, agent: current_agent, user: create(:user, tenant:))
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: current_agent,
          chat:,
          mission: nil, ui_context: nil,
          user: chat.user,
          tenant:,
          operation: nil,
        )

        result = described_class.new(nil, runtime_context:, current_agent:).execute(kind: "agents")

        expect(result).to include("`#{helper_agent.id}`", "Scoped Agent")
      end

      it "says when no agents exist" do
        expect(tool.execute(kind: "agents")).to include("No agents configured.")
      end
    end

    describe "missions" do
      it "lists other missions but not the current one" do
        other = create(:mission, name: "Other Flow")
        result = tool.execute(kind: "missions")
        expect(result).to include("Missions", "Other Flow", "`#{other.id}`")
        expect(result).not_to include("`#{mission.id}`")
      end

      it "lists all missions globally when no mission is provided" do
        existing = create(:mission, name: "Global Flow")
        expect(described_class.new.execute(kind: "missions")).to include("`#{existing.id}`")
      end

      it "says when no other missions exist" do
        expect(tool.execute(kind: "missions")).to include("No other missions available.")
      end
    end

    describe "clients" do
      it "lists tenant-scoped client channels through the legacy alias" do
        client = create(:channel, :client, tenant:, name: "Support Portal")
        create(:channel, :client, tenant: create(:tenant), name: "Foreign Client")

        result = tool.execute(kind: "clients")

        expect(result).to include("## Clients", "Support Portal", "`#{client.id}`")
        expect(result).not_to include("Foreign Client")
      end

      it "reports when no clients are available" do
        expect(tool.execute(kind: "clients")).to include("No clients available.")
      end

      it "reports when no scoped operation is available" do
        runtime_context = build_runtime_context(tenant:, operation: nil)

        expect(described_class.new(nil, runtime_context:).execute(kind: "clients"))
          .to include("No clients available.")
      end
    end

    describe "channels" do
      it "lists tenant-scoped channels" do
        channel = create(:channel, :api, tenant:, name: "Support API")
        create(:channel, :client, tenant: create(:tenant), name: "Foreign Channel")

        result = tool.execute(kind: "channels")

        expect(result).to include("## Channels", "Support API", "`#{channel.id}`")
        expect(result).not_to include("Foreign Channel")
      end

      it "reports when no channels are available" do
        expect(tool.execute(kind: "channels")).to include("No channels available.")
      end

      it "reports when no scoped operation is available" do
        runtime_context = build_runtime_context(tenant:, operation: nil)

        expect(described_class.new(nil, runtime_context:).execute(kind: "channels"))
          .to include("No channels available.")
      end
    end

    describe "skill_catalogs" do
      it "lists skill catalogs for the current operation" do
        catalog = create(:skill_catalog, operation: mission.operation, name: "Agent Manual")
        create(:skill_catalog, operation: create(:operation, tenant:), name: "Foreign Manual")

        result = tool.execute(kind: "skill_catalogs")

        expect(result).to include("Skill Catalogs", "Agent Manual", "`#{catalog.id}`")
        expect(result).not_to include("Foreign Manual")
      end

      it "uses the current agent operation when runtime context is missing" do
        current_agent = create(:agent, :enabled, operation: mission.operation, name: "Current Agent")
        catalog = create(:skill_catalog, operation: mission.operation, name: "Current Agent Manual")

        result = described_class.new(nil, current_agent:).execute(kind: "skill_catalogs")

        expect(result).to include("Skill Catalogs", "Current Agent Manual", "`#{catalog.id}`")
      end

      it "reports when no skill catalogs are available without a scoped operation" do
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: nil,
          chat: nil,
          mission: nil,
          ui_context: nil,
          user: nil,
          tenant:,
          operation: nil,
        )

        expect(described_class.new(nil, runtime_context:).execute(kind: "skill_catalogs"))
          .to include("No skill catalogs available.")
      end
    end

    describe "skills" do
      it "lists skills for the current operation" do
        local_catalog = create(:skill_catalog, operation: mission.operation, name: "Agent Manual")
        visible_skill = create(:skill, skill_catalog: local_catalog, name: "triage")
        foreign_catalog = create(:skill_catalog, operation: create(:operation, tenant:), name: "Foreign Manual")
        create(:skill, skill_catalog: foreign_catalog, name: "foreign")

        result = tool.execute(kind: "skills")

        expect(result).to include("## Skills", "triage", "Agent Manual", "`#{visible_skill.id}`")
        expect(result).not_to include("foreign")
      end

      it "reports when no operation-scoped skills are available" do
        runtime_context = BuiltinTools::RuntimeContext::Context.new(
          agent: nil,
          chat: nil,
          mission: nil,
          ui_context: nil,
          user: nil,
          tenant:,
          operation: nil,
        )

        expect(described_class.new(nil, runtime_context:).execute(kind: "skills"))
          .to include("No skills available.")
      end

      it "reports when the current operation has no skills" do
        expect(tool.execute(kind: "skills")).to include("No skills available.")
      end
    end

    describe "connectors" do
      it "lists tenant-scoped connectors with their type and status" do
        connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Prod LLM")
        disabled_connector = create(:connector, :llm_provider, tenant:, name: "Staging LLM")
        create(:connector, :sql_database, :enabled, tenant: create(:tenant), name: "Foreign DB")

        result = tool.execute(kind: "connectors")

        expect(result).to include("## Connectors", "Prod LLM", "enabled", "`#{connector.id}`")
        expect(result).to include("Staging LLM", "disabled", "`#{disabled_connector.id}`")
        expect(result).not_to include("Foreign DB")
      end

      it "reports when no connectors are available" do
        tenant.connectors.destroy_all

        expect(tool.execute(kind: "connectors")).to include("No connectors available.")
      end
    end

    describe "test_suites" do
      it "lists tenant-scoped test suites" do
        visible_suite = create(
          :test_suite,
          agent: create(:agent, operation: mission.operation),
          name: "Smoke Suite",
        )

        result = tool.execute(kind: "test_suites")

        expect(result).to include("## Test Suites", "Smoke Suite", "`#{visible_suite.id}`")
      end

      it "uses the mission name when a test suite has no agent target" do
        mission_stub = Struct.new(:name).new("Smoke Mission")
        test_suite_struct = Struct.new(:id, :name, :suite_type, :agent, :mission)
        mission_suite = test_suite_struct.new(88, "Mission Suite", "smoke", nil, mission_stub)
        allow(tool).to receive(:tenant_scoped_test_suites).and_return([mission_suite])

        result = tool.execute(kind: "test_suites")

        expect(result).to include("Mission Suite", "Smoke Mission")
      end

      it "reports when no test suites are available" do
        expect(tool.execute(kind: "test_suites")).to include("No test suites available.")
      end

      it "omits target detail when a test suite has no target record" do
        test_suite_struct = Struct.new(:id, :name, :suite_type, :agent, :mission)
        untargeted_suite = test_suite_struct.new(77, "Untargeted", nil, nil, nil)
        allow(tool).to receive(:tenant_scoped_test_suites).and_return([untargeted_suite])

        expect(tool.execute(kind: "test_suites")).to include("- `77` — Untargeted")
      end
    end

    describe "sql_database_connectors" do
      it "lists enabled SQL database connectors" do
        connector = create(:connector, :sql_database, :enabled, tenant:, name: "Analytics DB")

        result = tool.execute(kind: "sql_database_connectors")

        expect(result).to include("SQL Database Connectors", "Analytics DB", "`#{connector.id}`")
      end

      it "reports when no SQL database connectors are available" do
        expect(tool.execute(kind: "sql_database_connectors")).to include("No SQL database connectors available.")
      end
    end

    describe "mcp_server_connectors" do
      it "lists enabled MCP server connectors" do
        connector = create(:connector, :mcp_server, :enabled, tenant:, name: "Filesystem MCP")

        result = tool.execute(kind: "mcp_server_connectors")

        expect(result).to include("MCP Server Connectors", "Filesystem MCP", "`#{connector.id}`")
      end

      it "reports when no MCP server connectors are available" do
        expect(tool.execute(kind: "mcp_server_connectors")).to include("No MCP server connectors available.")
      end
    end

    describe "rag_flows" do
      it "lists RAG flows for the current operation" do
        allow(tool).to receive(:registered_resource_definitions).and_return({})
        flow = create(:rag_flow, operation: mission.operation, name: "Scoped Flow")
        create(:rag_flow, operation: create(:operation, tenant:), name: "Foreign Flow")

        result = tool.execute(kind: "rag_flows")

        expect(result).to include("RAG Flows", "Scoped Flow", "`#{flow.id}`")
        expect(result).not_to include("Foreign Flow")
      end

      it "falls back to tenant-scoped RAG flows when no operation is available" do
        list_tool = described_class.new
        allow(list_tool).to receive(:registered_resource_definitions).and_return({})
        visible_flow = create(:rag_flow, operation: tenant.default_operation, name: "Tenant Flow")
        create(:rag_flow, operation: create(:operation, tenant: create(:tenant)), name: "Foreign Flow")

        result = list_tool.execute(kind: "rag_flows")

        expect(result).to include("Tenant Flow", "`#{visible_flow.id}`")
        expect(result).not_to include("Foreign Flow")
      end

      it "reports when no RAG flows are available" do
        allow(tool).to receive(:registered_resource_definitions).and_return({})

        expect(tool.execute(kind: "rag_flows")).to include("No RAG flows available.")
      end
    end

    describe "capabilities" do
      it "lists available capability keys and field guidance" do
        result = tool.execute(kind: "capabilities")

        expect(result).to include("## Capabilities", "`chat_title_generator`", "`human_in_the_loop`", "`memory`")
        expect(result).to include("`max_length`", "`max_questions_per_call`", "`embedding_dimensions`")
        expect(result).to include("manage_capability")
      end

      it "reports when no capabilities are available" do
        allow(CapabilityPlugin).to receive(:all_types).and_return([])

        expect(tool.execute(kind: "capabilities")).to include("No capabilities available.")
      end

      it "handles capabilities without agent designer metadata helpers" do
        bare_capability = Class.new
        allow(CapabilityPlugin).to receive(:all_types).and_return(
          [{ key: "bare_capability", label: "Bare Capability", description: "Fallback metadata only." }],
        )
        allow(CapabilityPlugin).to receive(:resolve).with("bare_capability").and_return(bare_capability)

        result = tool.execute(kind: "capabilities")

        expect(result).to include("`bare_capability` — Bare Capability — Fallback metadata only.")
      end
    end

    describe "agent_types" do
      it "lists builtin agent types" do
        result = tool.execute(kind: "agent_types")

        expect(result).to include("## Agent Types")
        expect(result).to include("`mission_designer`", "`agent_designer`", "`channel_designer`")
      end

      it "reports when no builtin agent types are available" do
        allow(BuiltinAgents::DefinitionLoader).to receive(:load_all).and_return([])

        expect(tool.execute(kind: "agent_types")).to include("No agent types available.")
      end
    end

    it "falls back to the default tenant when no mission or runtime context is available" do
      Current.reset

      expect(described_class.new.send(:tenant)).to eq(Tenant.default_tenant)
    end

    it "uses the runtime_context tenant when no mission is provided" do
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant:,
        operation: mission.operation,
      )

      expect(described_class.new(nil, runtime_context:).send(:tenant)).to eq(tenant)
    end

    it "uses the current agent operation when mission and runtime context are missing" do
      current_agent = create(:agent, :enabled, operation: mission.operation, name: "Current Agent")

      expect(described_class.new(nil, current_agent:).send(:scoped_operation)).to eq(mission.operation)
    end

    it "falls back to the current headquarter operation when the tenant is unavailable" do
      other_tenant = create(:tenant).tap(&:ensure_core_resources!)
      other_user = create(:user, tenant: other_tenant)
      current_agent = create(
        :agent,
        :enabled,
        builtin: true,
        builtin_key: "agent_alpha",
        operation: other_tenant.headquarter_operation,
        name: "Agent Alpha",
      )
      runtime_context = build_runtime_context(
        agent: current_agent,
        chat: create(:chat, :application_context, agent: current_agent, user: other_user),
        tenant: nil,
        operation: nil,
      )
      Current.reset
      allow(Tenant).to receive(:default_tenant).and_return(nil)

      expect(described_class.new(nil, runtime_context:, current_agent:).send(:current_agent_operation_scope))
        .to eq(other_tenant.headquarter_operation)
    end

    it "does not treat a nil operation as an application-chat fallback trigger" do
      expect(described_class.new.send(:fallback_to_default_operation_for_application_chat?, nil)).to be_nil
    end

    it "requires a builtin current agent before applying the application-chat fallback" do
      expect(
        described_class.new.send(:fallback_to_default_operation_for_application_chat?, tenant.headquarter_operation),
      )
        .to be_nil
    end

    it "requires an application chat before applying the application-chat fallback" do
      current_agent = create(
        :agent,
        :enabled,
        builtin: true,
        builtin_key: "agent_alpha",
        operation: tenant.headquarter_operation,
        name: "Agent Alpha",
      )

      expect(
        described_class.new(nil, current_agent:).send(
          :fallback_to_default_operation_for_application_chat?,
          tenant.headquarter_operation,
        ),
      )
        .to be_nil
    end
  end
end
