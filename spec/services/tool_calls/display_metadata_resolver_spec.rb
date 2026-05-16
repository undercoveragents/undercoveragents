# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolCalls::DisplayMetadataResolver do
  describe ".resolve" do
    def create_widget_configured_sql_query_tool
      create(
        :tools_sql_query,
        tool_name: "Orders Explorer",
        tool_widget_icon: "fa-solid fa-bolt",
        tool_widget_running_mode: "rotate",
        tool_widget_running_interval_ms: 1300,
        tool_widget_running_messages: ["Crunching order history…"],
        tool_widget_complete_messages: ["Orders are ready."],
      )
    end

    def chat_for_assigned_tool(tool_record)
      agent = create(:agent)
      agent.tool_ids = [tool_record._tool_record.id]
      agent.save!
      create(:chat, agent:)
    end

    it "uses builtin runtime metadata when available" do
      result = described_class.resolve("read_mission_flow")

      expect(result).to have_attributes(
        display_name: "Read Mission Flow",
        icon: "fa-solid fa-diagram-project",
        group_title: "Working on the mission flow",
        running_mode: "rotate",
      )
      expect(result.running_messages).to include("Reading the current workflow graph…")
      expect(result.complete_messages).to include("Mission flow snapshot loaded.")
    end

    it "uses assigned tool metadata for dynamic tool names" do
      sql_query = create(:tools_sql_query, tool_name: "Orders Explorer")
      agent = create(:agent)
      agent.tool_ids = [sql_query._tool_record.id]
      agent.save!
      chat = create(:chat, agent:)

      result = described_class.resolve("sql_query_orders_explorer", chat:)

      expect(result.display_name).to eq("Orders Explorer")
      expect(result.icon).to eq("fa-solid fa-database")
    end

    it "merges shared widget configuration for assigned tools" do
      result = described_class.resolve(
        "sql_query_orders_explorer",
        chat: chat_for_assigned_tool(create_widget_configured_sql_query_tool),
      )

      expect(result).to have_attributes(
        icon: "fa-solid fa-bolt",
        running_mode: "rotate",
        running_interval_ms: 1300,
        running_messages: ["Crunching order history…"],
        complete_messages: ["Orders are ready."],
      )
      expect(result.group_title).to be_nil
    end

    it "normalizes the legacy sparkles icon for assigned tools" do
      sql_query = create(
        :tools_sql_query,
        tool_name: "Orders Explorer",
        tool_widget_icon: "fa-solid fa-sparkles",
      )
      agent = create(:agent)
      agent.tool_ids = [sql_query._tool_record.id]
      agent.save!
      chat = create(:chat, agent:)

      result = described_class.resolve("sql_query_orders_explorer", chat:)

      expect(result.icon).to eq("fa-solid fa-wand-magic-sparkles")
    end

    it "uses shared defaults when an assigned tool does not expose widget overrides" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      tool_record = instance_double(
        Tool,
        tool_type: "sql_query",
        name: "Orders Explorer",
        type_icon: "fa-solid fa-database",
        toolable: Object.new,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))

      result = described_class.resolve("sql_query_orders_explorer", chat:)

      expect(result.display_name).to eq("Orders Explorer")
      expect(result.icon).to eq("fa-solid fa-database")
      expect(result.running_messages).to include("Drafting a safe SQL query…")
    end

    it "falls back to shared defaults when widget override resolution raises" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      toolable = Object.new

      def toolable.tool_widget_override_presentation(*)
        raise StandardError, "boom"
      end

      tool_record = instance_double(
        Tool,
        tool_type: "sql_query",
        name: "Orders Explorer",
        type_icon: "fa-solid fa-database",
        toolable:,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))

      result = described_class.resolve("sql_query_orders_explorer", chat:)

      expect(result.display_name).to eq("Orders Explorer")
      expect(result.icon).to eq("fa-solid fa-database")
      expect(result.running_messages).to include("Drafting a safe SQL query…")
    end

    it "falls back cleanly when shared user-tool resolution raises" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      tool_record = instance_double(
        Tool,
        tool_type: "sql_query",
        name: "Orders Explorer",
        type_icon: "fa-solid fa-database",
        toolable: Object.new,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))
      allow(ToolCalls::PresentationDefaults).to receive(:resolve_user_tool).and_raise(StandardError, "boom")

      result = described_class.resolve("sql_query_orders_explorer", chat:)

      expect(result.display_name).to eq("Orders Explorer")
      expect(result.icon).to eq("fa-solid fa-database")
      expect(result.running_messages).to include("Working on Orders Explorer…")
    end

    it "falls back when tool runtime-name matching raises" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      tool_record = instance_double(Tool, tool_type: "custom_tool", toolable: nil)
      tool_class = Class.new do
        def self.tool_runtime_names(...)
          raise StandardError, "boom"
        end
      end

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))
      allow(ToolPlugin).to receive(:resolve).with("custom_tool").and_return(tool_class)

      result = described_class.resolve("custom_tool_runtime", chat:)

      expect(result.display_name).to eq("Custom Tool Runtime")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "humanizes MCP tool names while using the server icon" do
      mcp_tool = create(:tools_mcp_server, :with_tools, tool_name: "Filesystem")
      agent = create(:agent)
      agent.tool_ids = [mcp_tool._tool_record.id]
      agent.save!
      chat = create(:chat, agent:)

      result = described_class.resolve("list_directory", chat:)

      expect(result.display_name).to eq("List Directory")
      expect(result.icon).to eq("fa-solid fa-server")
    end

    it "matches discovered MCP tool names when no selected names are present" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      toolable = instance_double(
        Tools::McpServer,
        selected_tool_names: nil,
        all_discovered_tool_names: ["search_docs"],
      )
      tool_record = instance_double(
        Tool,
        tool_type: "mcp_server",
        name: "Filesystem",
        type_icon: "fa-solid fa-server",
        toolable:,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))

      result = described_class.resolve("search_docs", chat:)

      expect(result.display_name).to eq("Search Docs")
      expect(result.icon).to eq("fa-solid fa-server")
    end

    it "matches selected MCP tool names when no discovery list is present" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      toolable = instance_double(
        Tools::McpServer,
        selected_tool_names: ["read_file"],
        all_discovered_tool_names: nil,
      )
      tool_record = instance_double(
        Tool,
        tool_type: "mcp_server",
        name: "Filesystem",
        type_icon: "fa-solid fa-server",
        toolable:,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))

      result = described_class.resolve("read_file", chat:)

      expect(result.display_name).to eq("Read File")
      expect(result.icon).to eq("fa-solid fa-server")
    end

    it "falls back when an MCP tool record has no toolable metadata" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      tool_record = instance_double(
        Tool,
        tool_type: "mcp_server",
        name: "Filesystem",
        type_icon: "fa-solid fa-server",
        toolable: nil,
      )

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [tool_record]))

      result = described_class.resolve("read_file", chat:)

      expect(result.display_name).to eq("Read File")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "uses subagent names for subagent tools" do
      subagent = create(:agent, name: "Customer Support")
      agent = create(:agent)
      agent.subagent_ids = [subagent.id]
      agent.save!
      chat = create(:chat, agent:)

      result = described_class.resolve("ask_agent_customer_support", chat:)

      expect(result.display_name).to eq("Customer Support")
      expect(result.icon).to eq("fa-solid fa-robot")
    end

    it "falls back to a humanized label and heuristic icon" do
      result = described_class.resolve("archival_memory_search")

      expect(result.display_name).to eq("Archival Memory Search")
      expect(result.icon).to eq("fa-solid fa-box-archive")
    end

    it "uses the fallback robot icon when an ask_agent tool cannot be resolved to a subagent" do
      result = described_class.resolve("ask_agent_orphan")

      expect(result.display_name).to eq("Ask Agent Orphan")
      expect(result.icon).to eq("fa-solid fa-robot")
    end

    it "uses the fallback database icon for unresolved SQL-style tool names" do
      result = described_class.resolve("sql_query_custom_lookup")

      expect(result.display_name).to eq("SQL Query Custom Lookup")
      expect(result.icon).to eq("fa-solid fa-database")
    end

    it "uses the fallback brain icon for unresolved memory tool names" do
      result = described_class.resolve("memory_replace")

      expect(result.display_name).to eq("Memory Replace")
      expect(result.icon).to eq("fa-solid fa-brain")
    end

    it "uses the fallback skill icon for unresolved skill tool names" do
      result = described_class.resolve("skill_lookup")

      expect(result.display_name).to eq("Skill Lookup")
      expect(result.icon).to eq("fa-solid fa-book-open")
    end

    it "uses the fallback mission icon for unresolved flow-related tool names" do
      result = described_class.resolve("sync_flow_layout")

      expect(result.display_name).to eq("Sync Flow Layout")
      expect(result.icon).to eq("fa-solid fa-diagram-project")
    end

    it "uses the fallback test icon for unresolved test tool names" do
      result = described_class.resolve("test_case_runner")

      expect(result.display_name).to eq("Test Case Runner")
      expect(result.icon).to eq("fa-solid fa-vial")
    end

    it "uses the default icon when no fallback rule matches" do
      result = described_class.resolve("plain_tool")

      expect(result.display_name).to eq("Plain Tool")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "handles separator-only names through the humanized fallback path" do
      result = described_class.resolve("___")

      expect(result.display_name).to eq("")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "falls back to heuristic icons when a builtin definition has no icon" do
      original_definitions = BuiltinTools::Registry.definitions.dup

      BuiltinTools::Registry.register(
        "demo.memory_builtin",
        name: "Memory Builtin",
        description: "Demo",
        runtime_name: "memory_builtin",
      ) { nil }

      result = described_class.resolve("memory_builtin")

      expect(result.display_name).to eq("Memory Builtin")
      expect(result.icon).to eq("fa-solid fa-brain")
    ensure
      BuiltinTools::Registry.definitions.clear
      BuiltinTools::Registry.definitions.merge!(original_definitions)
    end

    it "falls back cleanly when MCP tool discovery metadata raises" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      failing_tool = instance_double(Tool, tool_type: "mcp_server")

      allow(failing_tool).to receive(:toolable).and_raise(StandardError, "boom")
      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [failing_tool]))

      result = described_class.resolve("read_file", chat:)

      expect(result.display_name).to eq("Read File")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "falls back when an assigned tool type has no runtime-name mapping" do
      agent = create(:agent)
      chat = create(:chat, agent:)
      unmapped_tool = instance_double(Tool, tool_type: "custom_tool", toolable: nil)

      allow(agent).to receive(:assigned_tools).and_return(double(enabled: [unmapped_tool]))

      result = described_class.resolve("custom_tool_runtime", chat:)

      expect(result.display_name).to eq("Custom Tool Runtime")
      expect(result.icon).to eq("fa-solid fa-wrench")
    end

    it "humanizes the runtime name when display-name resolution has no tool class" do
      resolver = described_class.new("sql_query_orders_explorer")
      tool_record = instance_double(Tool)

      allow(resolver).to receive(:toolable_for).with(tool_record).and_return(nil)
      allow(resolver).to receive(:resolve_tool_class).with(tool_record, nil).and_return(nil)

      expect(resolver.send(:tool_display_name, tool_record)).to eq("SQL Query Orders Explorer")
    end
  end
end
