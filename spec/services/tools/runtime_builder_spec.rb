# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::RuntimeBuilder do
  describe ".build" do
    it "builds sql query tools with the provided agent and parent chat" do
      tool_record = instance_double(Tool, tool_type: "sql_query", name: "SQL Helper")
      agent = instance_double(Agent)
      parent_chat = instance_double(Chat)
      built_tool = double("sql tool") # rubocop:disable RSpec/VerifiedDoubles

      allow(SqlQueryTool).to receive(:for_tool).with(tool_record, agent:, parent_chat:).and_return(built_tool)

      expect(described_class.build(tool_record, agent:, parent_chat:)).to eq(built_tool)
    end

    it "falls back to toolable_type when tool_type is unavailable" do
      legacy_tool_record = Struct.new(:toolable_type, :name).new("Tools::McpServer", "Filesystem")
      built_tools = [double("mcp tool")] # rubocop:disable RSpec/VerifiedDoubles

      allow(ToolPlugin).to receive(:filter_type).with("Tools::McpServer").and_return("mcp_server")
      allow(McpServerTool).to receive(:for_tool).with(legacy_tool_record).and_return(built_tools)

      expect(described_class.build(legacy_tool_record)).to eq(built_tools)
    end

    it "returns nil for unknown tool types" do
      tool_record = instance_double(Tool, tool_type: "unknown", name: "Mystery Tool")

      expect(described_class.build(tool_record)).to be_nil
    end

    it "logs a fallback tool name when a nameless tool record fails to build" do
      nameless_tool_record = Struct.new(:tool_type).new("mcp_server")

      allow(McpServerTool).to receive(:for_tool).with(nameless_tool_record).and_raise(StandardError, "boom")
      allow(Rails.logger).to receive(:error)

      expect(described_class.build(nameless_tool_record)).to be_nil
      expect(Rails.logger).to have_received(:error)
        .with("[Tools::RuntimeBuilder] Failed to build tool 'unknown': boom")
    end
  end

  describe ".build_many" do
    it "flattens array-returning builders and drops nil entries" do
      mcp_tool = instance_double(Tool, tool_type: "mcp_server", name: "Filesystem")
      unknown_tool = instance_double(Tool, tool_type: "unknown", name: "Unknown")
      built_a = double("built a") # rubocop:disable RSpec/VerifiedDoubles
      built_b = double("built b") # rubocop:disable RSpec/VerifiedDoubles

      allow(McpServerTool).to receive(:for_tool).with(mcp_tool).and_return([built_a, built_b])

      expect(described_class.build_many([mcp_tool, unknown_tool])).to eq([built_a, built_b])
    end
  end
end
