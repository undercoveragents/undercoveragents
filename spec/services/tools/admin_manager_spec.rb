# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::AdminManager do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:sql_connector) { create(:connector, :sql_database, tenant:) }
  let(:mcp_connector) { create(:connector, :mcp_server, tenant:) }
  let(:manager) { described_class.new }

  def discovered_schema
    {
      "objects" => [
        {
          "name" => "users",
          "columns" => [{ "name" => "id" }],
        },
        {
          "name" => "orders",
          "columns" => [{ "name" => "id" }],
        },
      ],
    }
  end

  def build_broken_visibility_tool_class
    stub_const("BrokenVisibilityTool", Class.new do
      include ToolPlugin

      def self.tool_designer_actions = [{ "key" => "set_visibility", "description" => "Broken visibility." }]

      def self.tool_designer_action_definition(action_key)
        tool_designer_actions.find { |action| action.fetch("key") == action_key.to_s }
      end

      def self.type_label = "Broken Visibility"

      def visibility_param_key = nil
    end,)
    BrokenVisibilityTool
  end

  describe "#build" do
    it "builds a tool with canonical toolable attributes", :aggregate_failures do
      tool = manager.build(
        operation:,
        tool_type: "sql_query",
        tool_attributes: { name: "Orders Explorer", description: "Reads orders", enabled: true },
        toolable_attributes: { connector_id: sql_connector.id, llm_config_source: "inherit" },
      )

      expect(tool).to be_a(Tool)
      expect(tool).not_to be_persisted
      expect(tool).to have_attributes(name: "Orders Explorer", description: "Reads orders", enabled: true)
      expect(tool.toolable).to be_a(Tools::SqlQuery)
      expect(tool.toolable.connector_id).to eq(sql_connector.id)
    end

    it "rejects unknown tool types" do
      expect do
        manager.build(
          operation:,
          tool_type: "unknown_tool",
          tool_attributes: { name: "Broken Tool" },
          toolable_attributes: {},
        )
      end.to raise_error(ArgumentError, "Unknown tool type 'unknown_tool'.")
    end

    it "rejects unknown top-level tool attributes" do
      expect do
        manager.build(
          operation:,
          tool_type: "sql_query",
          tool_attributes: { slug: "not-allowed" },
          toolable_attributes: { connector_id: sql_connector.id },
        )
      end.to raise_error(ArgumentError, "Unknown tool attributes: slug")
    end

    it "rejects unknown type-specific attributes" do
      expect do
        manager.build(
          operation:,
          tool_type: "sql_query",
          tool_attributes: { name: "Orders Explorer" },
          toolable_attributes: { bad_key: true },
        )
      end.to raise_error(ArgumentError, "Unknown SQL Query configuration keys: bad_key")
    end

    it "builds a tool from controller params through the plugin" do
      tool = manager.build_from_params(
        operation:,
        tool_type: "sql_query",
        tool_attributes: { name: "Orders Explorer" },
        params: ActionController::Parameters.new(
          sql_query: { connector_id: sql_connector.id, llm_config_source: "inherit" },
        ),
      )

      expect(tool.toolable).to have_attributes(connector_id: sql_connector.id, llm_config_source: "inherit")
    end
  end

  describe "#parse_hash" do
    it "parses ActionController parameters" do
      params = ActionController::Parameters.new(name: "Orders Explorer")

      expect(manager.parse_hash(params)).to eq({ "name" => "Orders Explorer" })
    end

    it "parses stringified JSON objects" do
      expect(manager.parse_hash('{"name":"Orders Explorer"}')).to eq({ "name" => "Orders Explorer" })
    end
  end

  describe "#update!" do
    let(:tool_record) do
      create(
        :tool,
        operation:,
        name: "Orders Explorer",
        toolable: Tools::SqlQuery.new(connector_id: sql_connector.id, llm_config_source: "inherit"),
      )
    end

    it "updates tool fields and toolable configuration using widget aliases", :aggregate_failures do
      manager.update!(
        tool: tool_record,
        tool_attributes: { description: "Updated description" },
        toolable_attributes: {
          instructions: "Use this tool for reporting only.",
          icon: "fa-solid fa-bolt",
        },
      )

      expect(tool_record.reload.description).to eq("Updated description")
      expect(tool_record.configuration["instructions"]).to eq("Use this tool for reporting only.")
      expect(tool_record.configuration["tool_widget_icon"]).to eq("fa-solid fa-bolt")
    end

    it "requires at least one change" do
      expect { manager.update!(tool: tool_record) }
        .to raise_error(ArgumentError, "Provide tool_attributes and/or toolable_attributes.")
    end

    it "updates a tool from controller params through the plugin", :aggregate_failures do
      manager.update_from_params!(
        tool: tool_record,
        tool_attributes: { name: "Orders Renamed" },
        params: ActionController::Parameters.new(
          sql_query: { connector_id: sql_connector.id, llm_config_source: "inherit" },
        ),
      )

      expect(tool_record.reload.name).to eq("Orders Renamed")
      expect(tool_record.toolable.llm_config_source).to eq("inherit")
    end

    it "updates only top-level tool attributes when toolable attributes are blank" do
      manager.update!(tool: tool_record, tool_attributes: { description: "Renamed only" })

      expect(tool_record.reload.description).to eq("Renamed only")
    end

    it "updates only toolable configuration when tool attributes are blank" do
      manager.update!(tool: tool_record, toolable_attributes: { instructions: "Tool-only change" })

      expect(tool_record.reload.configuration["instructions"]).to eq("Tool-only change")
    end

    it "destroys tools" do
      tool_record

      expect { manager.destroy!(tool: tool_record) }.to change(Tool, :count).by(-1)
    end
  end

  describe "#perform_action!" do
    let(:sql_tool) do
      create(
        :tool,
        operation:,
        name: "Orders Explorer",
        toolable: Tools::SqlQuery.new(
          connector_id: sql_connector.id,
          llm_config_source: "inherit",
          discovered_schema:,
          schema_discovered_at: Time.current,
          selected_objects: [{ "name" => "users" }, { "name" => "orders" }],
        ),
      )
    end

    it "delegates discovery to the tool plugin" do
      allow(sql_tool.toolable).to receive(:perform_discovery!)
        .and_return(ToolPlugin::Result.new(success?: true, message: "Schema discovered"))

      result = manager.perform_action!(tool: sql_tool, action: "discover")

      expect(result).to eq(described_class::ActionResult.new(success?: true, message: "Schema discovered"))
    end

    it "reports discovery errors" do
      allow(sql_tool.toolable).to receive(:perform_discovery!)
        .and_return(ToolPlugin::Result.new(success?: false, message: "Connection refused"))

      result = manager.perform_action!(tool: sql_tool, action: "discover")

      expect(result).to eq(described_class::ActionResult.new(success?: false, message: "Connection refused"))
    end

    it "updates visibility through the tool-specific param key", :aggregate_failures do
      result = manager.perform_action!(tool: sql_tool, action: "set_visibility", selected_items: ["users"])

      expect(result).to eq(
        described_class::ActionResult.new(success?: true, message: I18n.t("tools.visibility_updated")),
      )
      expect(sql_tool.reload.toolable.selected_object_names).to eq(["users"])
    end

    it "rejects unsupported actions" do
      mission_tool = create(
        :tool,
        operation:,
        name: "Run Mission",
        toolable: Tools::MissionTool.new(mission_id: create(:mission, operation:).id),
      )

      expect { manager.perform_action!(tool: mission_tool, action: "discover") }
        .to raise_error(ArgumentError, "Action 'discover' is not supported for Mission.")
    end

    it "rejects unknown actions" do
      message = "Action 'unknown' is not supported for SQL Query. Use discover, set_visibility."

      expect { manager.perform_action!(tool: sql_tool, action: "unknown") }
        .to raise_error(ArgumentError, message)
    end

    it "rejects blank actions" do
      expect { manager.perform_action!(tool: sql_tool, action: " ") }
        .to raise_error(ArgumentError, "Provide an action.")
    end

    it "raises when visibility is requested without a parameter key" do
      broken_tool = instance_double(
        Tool,
        toolable: build_broken_visibility_tool_class.new,
        type_label: "Broken Visibility",
        tool_type: "broken_visibility",
      )

      expect { manager.perform_action!(tool: broken_tool, action: "set_visibility") }
        .to raise_error(ArgumentError, "Visibility updates are not supported for Broken Visibility.")
    end
  end

  describe "parsing helpers" do
    it "parses JSON object strings into hashes" do
      expect(manager.parse_hash('{"name":"Orders Explorer"}')).to eq("name" => "Orders Explorer")
    end

    it "rejects unsupported parse_hash inputs" do
      expect { manager.parse_hash(123) }.to raise_error(ArgumentError, "Expected a hash or JSON object string.")
    end

    it "treats blank JSON strings as empty hashes" do
      expect(manager.parse_string_hash("   ")).to eq({})
    end

    it "rejects JSON strings that do not decode to objects" do
      expect { manager.parse_string_hash("[]") }.to raise_error(ArgumentError, "Expected a JSON object.")
    end

    it "keeps canonical widget keys when aliases are also provided" do
      normalized = manager.normalize_toolable_attributes(
        "icon" => "fa-solid fa-bolt",
        "tool_widget_icon" => "fa-solid fa-database",
      )

      expect(normalized).to eq("tool_widget_icon" => "fa-solid fa-database")
    end
  end
end
