# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolsHelper do
  describe "#tool_type_label" do
    it "returns 'SQL Query' for SQL Query tools" do
      tool = build(:tool, :sql_query)
      expect(helper.tool_type_label(tool)).to eq("SQL Query")
    end

    it "returns 'MCP Server' for MCP Server tools" do
      tool = build(:tool, :mcp_server)
      expect(helper.tool_type_label(tool)).to eq("MCP Server")
    end

    it "returns 'RAG Query' for RAG Query tools" do
      tool = build(:tool, :rag_query)
      expect(helper.tool_type_label(tool)).to eq("RAG Query")
    end
  end

  describe "#tool_type_icon" do
    it "returns database icon for SQL Query tools" do
      tool = build(:tool, :sql_query)
      expect(helper.tool_type_icon(tool)).to eq("fa-solid fa-database")
    end

    it "returns server icon for MCP Server tools" do
      tool = build(:tool, :mcp_server)
      expect(helper.tool_type_icon(tool)).to eq("fa-solid fa-server")
    end

    it "returns magnifying glass icon for RAG Query tools" do
      tool = build(:tool, :rag_query)
      expect(helper.tool_type_icon(tool)).to eq("fa-solid fa-magnifying-glass")
    end
  end

  describe "#tool_status_label" do
    it "returns 'Active' when enabled" do
      tool = build(:tool, :sql_query, :enabled)
      expect(helper.tool_status_label(tool)).to eq("Active")
    end

    it "returns 'Inactive' when disabled" do
      tool = build(:tool, :sql_query, :disabled)
      expect(helper.tool_status_label(tool)).to eq("Inactive")
    end
  end

  describe "#tool_status_color" do
    it "returns 'success' when enabled" do
      tool = build(:tool, :sql_query, :enabled)
      expect(helper.tool_status_color(tool)).to eq("success")
    end

    it "returns 'warning' when disabled" do
      tool = build(:tool, :sql_query, :disabled)
      expect(helper.tool_status_color(tool)).to eq("warning")
    end
  end

  describe "#tool_status_badge" do
    it "returns a success badge for enabled tools" do
      tool = build(:tool, :sql_query, :enabled)
      badge = helper.tool_status_badge(tool)
      expect(badge).to include("badge-success")
      expect(badge).to include("Active")
    end

    it "returns a warning badge for disabled tools" do
      tool = build(:tool, :sql_query, :disabled)
      badge = helper.tool_status_badge(tool)
      expect(badge).to include("badge-warning")
      expect(badge).to include("Inactive")
    end
  end

  describe "#tool_connector_display" do
    it "returns the connector name for SQL Query tools" do
      connector = create(:connector, :sql_database, name: "My DB")
      sq = create(:tools_sql_query, connector:)
      tool = create(:tool, toolable: sq)

      expect(helper.tool_connector_display(tool)).to eq("My DB")
    end

    it "returns the connector name for MCP Server tools" do
      connector = create(:connector, :mcp_server, name: "My MCP")
      mcp = create(:tools_mcp_server, connector:)
      tool = create(:tool, toolable: mcp)

      expect(helper.tool_connector_display(tool)).to eq("My MCP")
    end

    it "returns dash when toolable has no connector method" do
      tool = build(:tool, :sql_query)
      allow(tool.toolable).to receive(:respond_to?).with(:connector).and_return(false)

      expect(helper.tool_connector_display(tool)).to eq("—")
    end

    it "returns 'Unknown' when connector is nil" do
      tool = build(:tool, :sql_query)
      allow(tool.toolable).to receive(:connector).and_return(nil)

      expect(helper.tool_connector_display(tool)).to eq("Unknown")
    end
  end

  describe "#tool_compaction_policy_label" do
    let(:toolable_class) do
      Class.new do
        attr_reader :tool_compaction_policy

        def initialize(policy)
          @tool_compaction_policy = policy
        end
      end
    end

    context "when the policy is blank" do
      it "returns Default" do
        expect(helper.tool_compaction_policy_label(toolable_class.new(""))).to eq("Default")
      end
    end

    context "when the policy matches a known option" do
      it "returns the matching label" do
        expect(helper.tool_compaction_policy_label(toolable_class.new("drop_all")))
          .to eq("Drop all (stub every past result)")
      end
    end

    context "when the policy does not match any known option" do
      it "falls back to Default" do
        expect(helper.tool_compaction_policy_label(toolable_class.new("unknown_policy")))
          .to eq("Default")
      end
    end
  end

  describe "tool widget helpers" do
    it "falls back to the tool defaults when the toolable has no widget override hook" do
      tool = build_stubbed(:tool, tool_type: "sql_query", name: "Orders Explorer")
      plain_toolable_class = Class.new do
        def self.type_key = "sql_query"
        def self.type_icon = "fa-solid fa-database"
        def self.type_label = "SQL Query"
      end

      presentation = helper.tool_widget_resolved_presentation(tool, plain_toolable_class.new)

      expect(presentation.display_name).to eq("Orders Explorer")
      expect(presentation.icon).to eq("fa-solid fa-database")
      expect(presentation.running_messages).to include("Drafting a safe SQL query…")
    end

    it "uses the free sparkles preset icon class" do
      toolable_class = Class.new do
        def self.type_icon = "fa-solid fa-database"
      end

      presets = helper.tool_widget_icon_presets(toolable_class.new)

      expect(presets).to include("fa-solid fa-wand-magic-sparkles")
      expect(presets).not_to include("fa-solid fa-sparkles")
    end

    it "returns the rotate label for rotating widgets" do
      expect(helper.tool_widget_running_mode_label("rotate")).to eq("Rotates while running")
    end

    it "builds icon field options with normalized widget icons" do
      toolable = Struct.new(:tool_widget_icon).new("fa-solid fa-sparkles")
      default_presentation = ToolCalls::Presentation.new(
        display_name: "Mission Designer",
        icon: "fa-solid fa-diagram-project",
      )

      options = helper.tool_widget_icon_field_options(toolable, default_presentation)

      expect(options[:value]).to eq("fa-solid fa-wand-magic-sparkles")
      expect(options[:placeholder]).to eq("fa-solid fa-diagram-project")
    end

    it "builds widget message textarea options from newline-separated messages" do
      options = helper.tool_widget_messages_field_options(
        ["Reading the flow…", "Updating the nodes…"],
        ["Working on it…"],
      )

      expect(options[:value]).to eq("Reading the flow…\nUpdating the nodes…")
      expect(options[:placeholder]).to eq("Working on it…")
    end
  end
end
