# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::ToolTypeInfoTool do
  let(:tool_record) do
    tenant = create(:tenant).tap(&:ensure_core_resources!)
    operation = tenant.default_operation
    connector = create(:connector, :sql_database, tenant:)

    create(
      :tool,
      operation:,
      name: "Orders Explorer",
      toolable: Tools::SqlQuery.new(connector_id: connector.id, llm_config_source: "inherit"),
    )
  end

  describe "#execute" do
    it "returns info for the current tool type when the param is omitted" do
      result = described_class.new(current_tool: tool_record).execute

      expect(result).to include(
        "## Tool Type",
        "`sql_query`",
        "## Common Tool Fields",
        "## Type-Specific Editable Fields",
        "`connector_id`",
        "## Supported Actions",
        "`discover`",
        "## Notes",
      )
    end

    it "returns a helpful message when there is no tool type context" do
      expect(described_class.new.execute).to eq("Provide tool_type or open a tool page first.")
    end

    it "reports unknown tool types" do
      expect(described_class.new.execute(tool_type: "missing_tool")).to eq(
        "Unknown tool type 'missing_tool'. Use list_resources(kind: \"tool_types\").",
      )
    end

    it "rescues unexpected errors" do
      allow(ToolDesigner::TypeCatalog).to receive(:new).and_raise(StandardError, "boom")

      expect(described_class.new(current_tool: tool_record).execute).to eq("Error reading tool type info: boom")
    end
  end
end
