# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::ReadToolTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
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
  let(:connector) { create(:connector, :sql_database, tenant:) }
  let(:tool_record) do
    create(
      :tool,
      :enabled,
      operation:,
      name: "Orders Explorer",
      description: "Reads the order catalog",
      toolable: Tools::SqlQuery.new(
        connector_id: connector.id,
        llm_config_source: "inherit",
        discovered_schema: {
          "objects" => [
            { "name" => "users", "columns" => [{ "name" => "id" }] },
          ],
        },
        schema_discovered_at: Time.current,
        selected_objects: [{ "name" => "users" }],
      ),
    )
  end

  describe "#execute" do
    it "reads the current tool configuration, assignments, and type guidance" do
      agent = create(:agent, operation:, name: "Analyst", model_id: "gpt-4.1")
      agent.assigned_tool_ids = [tool_record.id]
      agent.save!

      result = described_class.new(runtime_context:, current_tool: tool_record).execute

      expect(result).to include(
        "## Tool",
        "Orders Explorer",
        "## Assigned Agents",
        "Analyst",
        "## Current Tool State",
        "Visible objects",
        "Discovered objects",
        "## Current Configuration",
        "## Admin Actions",
        "manage_record(action: \"clone\", resource: \"tool\"",
        "## Tool Type",
        "`connector_id`",
        "`discover`",
      )
    end

    it "finds a tool by id inside the current operation" do
      foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
      foreign_tool = create(
        :tool,
        operation: foreign_tenant.default_operation,
        name: "Foreign Tool",
        toolable: Tools::McpServer.new(connector_id: create(:connector, :mcp_server, tenant: foreign_tenant).id),
      )
      tool = described_class.new(runtime_context:)

      expect(tool.execute(tool_id: tool_record.id)).to include("Orders Explorer")
      expect(tool.execute(tool_id: foreign_tool.id)).to eq("Error: Tool '#{foreign_tool.id}' was not found.")
    end

    it "returns a helpful message when there is no current tool" do
      result = described_class.new(runtime_context:).execute

      expect(result).to eq(
        "No current tool is available. Pass tool_id after creating one or open a tool page first.",
      )
    end

    it "renders empty discovered selections as none" do
      empty_tool = create(
        :tool,
        operation:,
        name: "Empty Explorer",
        toolable: Tools::SqlQuery.new(
          connector_id: connector.id,
          llm_config_source: "inherit",
          selected_objects: [],
        ),
      )

      result = described_class.new(runtime_context:, current_tool: empty_tool).execute

      expect(result).to include("Visible objects: none")
    end

    it "omits the state section when a tool type exposes no tracked state" do
      mission_tool = create(
        :tool,
        operation:,
        name: "Run Mission",
        toolable: Tools::MissionTool.new(mission_id: create(:mission, operation:).id),
      )

      result = described_class.new(runtime_context:, current_tool: mission_tool).execute

      expect(result).not_to include("## Current Tool State")
    end

    it "rescues unexpected rendering errors" do
      tool = described_class.new(runtime_context:, current_tool: tool_record)
      allow(tool).to receive(:summary_section).and_raise(StandardError, "boom")

      expect(tool.execute).to eq("Error reading tool: boom")
    end

    it "formats edge-case state values" do
      tool = described_class.new(runtime_context:, current_tool: tool_record)

      expect(tool.send(:tool_state_line, { "value" => "missing label" })).to be_nil
      expect(tool.send(:format_state_value, ["users"])).to eq("`users`")
      expect(tool.send(:format_state_value, { "count" => 1 })).to eq('`{"count":1}`')
    end
  end
end
