# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectorsHelper do
  describe "#connector_type_label" do
    it "returns 'SQL Database' for SQL connectors" do
      connector = build(:connector, :sql_database)
      expect(helper.connector_type_label(connector)).to eq("SQL Database")
    end

    it "returns 'LLM Provider' for LLM connectors" do
      connector = build(:connector, :llm_provider)
      expect(helper.connector_type_label(connector)).to eq("LLM Provider")
    end

    it "returns 'MCP Server' for MCP connectors" do
      connector = build(:connector, :mcp_server)
      expect(helper.connector_type_label(connector)).to eq("MCP Server")
    end

    it "returns 'Authentication' for authentication connectors" do
      connector = build(:connector, :authentication)
      expect(helper.connector_type_label(connector)).to eq("Authentication")
    end

    it "returns titleized name for unknown types" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:connector_type).and_return("some_other_thing")
      expect(helper.connector_type_label(connector)).to eq("Some Other Thing")
    end
  end

  describe "#connector_type_icon" do
    it "returns database icon for SQL connectors" do
      connector = build(:connector, :sql_database)
      expect(helper.connector_type_icon(connector)).to eq("fa-solid fa-database")
    end

    it "returns brain icon for LLM connectors" do
      connector = build(:connector, :llm_provider)
      expect(helper.connector_type_icon(connector)).to eq("fa-solid fa-brain")
    end

    it "returns server icon for MCP connectors" do
      connector = build(:connector, :mcp_server)
      expect(helper.connector_type_icon(connector)).to eq("fa-solid fa-server")
    end

    it "returns shield icon for authentication connectors" do
      connector = build(:connector, :authentication)
      expect(helper.connector_type_icon(connector)).to eq("fa-solid fa-shield-halved")
    end

    it "returns plug icon for unknown connector types" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:connector_type).and_return("unknown_type")
      expect(helper.connector_type_icon(connector)).to eq("fa-solid fa-plug")
    end
  end

  describe "#connector_status_label" do
    it "returns 'Active' when enabled" do
      connector = build(:connector, :sql_database, :enabled)
      expect(helper.connector_status_label(connector)).to eq("Active")
    end

    it "returns 'Inactive' when disabled" do
      connector = build(:connector, :sql_database, :disabled)
      expect(helper.connector_status_label(connector)).to eq("Inactive")
    end
  end

  describe "#connector_status_color" do
    it "returns 'success' when enabled" do
      connector = build(:connector, :sql_database, :enabled)
      expect(helper.connector_status_color(connector)).to eq("success")
    end

    it "returns 'warning' when disabled" do
      connector = build(:connector, :sql_database, :disabled)
      expect(helper.connector_status_color(connector)).to eq("warning")
    end
  end

  describe "#connector_status_badge" do
    it "returns a success badge for enabled connectors" do
      connector = build(:connector, :sql_database, :enabled)
      badge = helper.connector_status_badge(connector)

      expect(badge).to include("badge-success")
      expect(badge).to include("Active")
    end

    it "returns a warning badge for disabled connectors" do
      connector = build(:connector, :sql_database, :disabled)
      badge = helper.connector_status_badge(connector)

      expect(badge).to include("badge-warning")
      expect(badge).to include("Inactive")
    end
  end

  describe "#transport_type_label" do
    it "returns 'STDIO (Local Command)' for stdio" do
      expect(helper.transport_type_label("stdio")).to eq("STDIO (Local Command)")
    end

    it "returns 'SSE (Server-Sent Events)' for sse" do
      expect(helper.transport_type_label("sse")).to eq("SSE (Server-Sent Events)")
    end

    it "returns 'Streamable HTTP' for streamable_http" do
      expect(helper.transport_type_label("streamable_http")).to eq("Streamable HTTP")
    end

    it "returns titleized label for unknown transport" do
      expect(helper.transport_type_label("custom_ws")).to eq("Custom Ws")
    end
  end
end
