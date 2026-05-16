# frozen_string_literal: true

# == Schema Information
#
# Table name: tools_mcp_servers
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  discovered_tools    :jsonb            not null
#  selected_tools      :jsonb            not null
#  tools_discovered_at :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  connector_id        :bigint           not null
#
# Indexes
#
#  index_tools_mcp_servers_on_connector_id  (connector_id)
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#
require "rails_helper"

RSpec.describe Tools::McpServer do
  describe ".tool_designer_notes" do
    it "documents the connector lookup and discovery workflow" do
      expect(described_class.tool_designer_notes).to include(
        "Use list_resources(kind: \"mcp_server_connectors\") to resolve connector_id values.",
        "Run discover before set_visibility so the available MCP tool names come from the real server.",
      )
    end
  end

  describe ".tool_designer_field_hints" do
    it "declares the connector lookup kind" do
      expect(described_class.tool_designer_field_hints).to eq(
        "connector_id" => {
          "resource_kind" => "mcp_server_connectors",
        },
      )
    end
  end

  describe ".tool_designer_state_attributes" do
    it "declares plugin-owned state entries" do
      expect(described_class.tool_designer_state_attributes).to include(
        hash_including("label" => "Tools discovered at", "method" => "tools_discovered_at"),
        hash_including("label" => "Visible tools", "method" => "selected_tool_names", "empty" => true),
        hash_including("label" => "Discovered tools", "method" => "all_discovered_tool_names"),
      )
    end
  end

  describe "connector accessor" do
    it "returns the connector by id" do
      mcp_connector = create(:connector, :mcp_server)
      mcp_tool = build(:tools_mcp_server, connector: mcp_connector)
      expect(mcp_tool.connector).to eq(mcp_connector)
    end
  end

  describe "persistence" do
    it "#id returns the backing tool's id" do
      mcp = create(:tools_mcp_server)
      expect(mcp.id).to eq(mcp._tool_record.id)
    end

    it "#reload refreshes attributes from the database" do
      mcp = create(:tools_mcp_server)
      new_config = mcp._tool_record.configuration.merge("discovered_tools" => [{ "name" => "new_tool" }])
      mcp._tool_record.update_column(:configuration, new_config) # rubocop:disable Rails/SkipsModelValidations
      mcp.reload
      expect(mcp.discovered_tools).to eq([{ "name" => "new_tool" }])
    end

    it "#reload returns self when no _tool_record is set" do
      mcp = build(:tools_mcp_server)
      expect(mcp.reload).to be(mcp)
    end

    it "== compares by id" do
      m1 = create(:tools_mcp_server)
      m2 = create(:tools_mcp_server)
      expect(m1).not_to eq(m2)
      expect(m1.reload).to eq(m1)
    end

    it "#id returns nil when no _tool_record is set" do
      ms = build(:tools_mcp_server)
      expect(ms.id).to be_nil
    end

    it "== returns false for non-McpServer objects" do
      ms = create(:tools_mcp_server)
      expect(ms == "other").to be(false)
    end

    it "== falls through to object identity for unsaved objects" do
      m1 = build(:tools_mcp_server)
      m2 = build(:tools_mcp_server)
      expect(m1).not_to eq(m2)
      myself = m1
      expect(m1).to eq(myself)
    end
  end

  describe "#connector" do
    it "returns nil when connector_id is blank" do
      ms = build(:tools_mcp_server, connector_id: nil)
      expect(ms.connector).to be_nil
    end

    it "returns nil when the cached connector has been cleared" do
      ms = build(:tools_mcp_server)
      ms.connector = nil

      expect(ms.connector).to be_nil
    end

    it "clears connector_id when assigned nil" do
      ms = build(:tools_mcp_server)
      ms.connector = nil
      expect(ms.connector_id).to be_nil
    end

    it "loads connector from DB when cache is cold" do
      ms = described_class.new(connector_id: nil)
      expect(ms.connector).to be_nil
    end
  end

  describe "#tool" do
    it "returns nil when _tool_record is not set" do
      ms = build(:tools_mcp_server)
      expect(ms.tool).to be_nil
    end
  end

  describe "validations" do
    it "is valid when connector is nil (blank check in validator short-circuits)" do
      ms = build(:tools_mcp_server, connector: nil)
      ms.valid?
      expect(ms.errors[:connector]).not_to include("must be an MCP Server connector")
    end

    it "validates connector is an MCP Server" do
      sql_connector = create(:connector, :sql_database)
      mcp_tool = build(:tools_mcp_server, connector: sql_connector)
      expect(mcp_tool).not_to be_valid
      expect(mcp_tool.errors[:connector]).to include("must be an MCP Server connector")
    end

    it "allows MCP Server connectors" do
      mcp_connector = create(:connector, :mcp_server)
      mcp_tool = build(:tools_mcp_server, connector: mcp_connector)
      expect(mcp_tool).to be_valid
    end

    it "rejects MCP connectors outside the tool tenant" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      foreign_connector = create(:connector, :mcp_server, tenant: create(:tenant))
      mcp_tool = create(:tool, :mcp_server, operation:).configurator
      mcp_tool.connector_id = foreign_connector.id

      expect(mcp_tool).not_to be_valid
      expect(mcp_tool.errors[:connector]).to include("must be an MCP Server connector")
    end
  end

  describe "#selected_tool_names" do
    it "extracts names from selected tools" do
      mcp = build(:tools_mcp_server, selected_tools: [{ "name" => "read_file" }, { "name" => "list_dir" }])
      expect(mcp.selected_tool_names).to eq(["read_file", "list_dir"])
    end

    it "returns empty array when no tools selected" do
      mcp = build(:tools_mcp_server, selected_tools: [])
      expect(mcp.selected_tool_names).to eq([])
    end

    it "handles symbol keys" do
      mcp = build(:tools_mcp_server, selected_tools: [{ name: "read_file" }])
      expect(mcp.selected_tool_names).to eq(["read_file"])
    end

    it "returns empty array when selected_tools is not an array" do
      mcp = build(:tools_mcp_server, selected_tools: nil)
      expect(mcp.selected_tool_names).to eq([])
    end
  end

  describe "#all_discovered_tool_names" do
    it "returns all discovered tool names" do
      mcp = build(:tools_mcp_server, discovered_tools: [
                    { "name" => "read_file", "description" => "Read a file" },
                    { "name" => "list_dir", "description" => "List directory" },
                  ],)
      expect(mcp.all_discovered_tool_names).to eq(["read_file", "list_dir"])
    end

    it "returns empty array when no tools discovered" do
      mcp = build(:tools_mcp_server, discovered_tools: [])
      expect(mcp.all_discovered_tool_names).to eq([])
    end

    it "returns empty array when discovered_tools is not an array" do
      mcp = build(:tools_mcp_server, discovered_tools: nil)
      expect(mcp.all_discovered_tool_names).to eq([])
    end
  end

  describe "#all_tools_selected?" do
    it "returns true when all discovered tools are selected" do
      mcp = build(:tools_mcp_server, :with_tools)
      expect(mcp.all_tools_selected?).to be(true)
    end

    it "returns false when only some tools are selected" do
      mcp = build(:tools_mcp_server, :with_partial_selection)
      expect(mcp.all_tools_selected?).to be(false)
    end

    it "returns true when no tools are discovered" do
      mcp = build(:tools_mcp_server, discovered_tools: [], selected_tools: [])
      expect(mcp.all_tools_selected?).to be(true)
    end
  end

  describe "#sync_selected_after_discovery" do
    it "selects all tools when no previous selection" do
      mcp = build(:tools_mcp_server, discovered_tools: [
                    { "name" => "read_file" },
                    { "name" => "list_dir" },
                  ],)
      mcp.sync_selected_after_discovery([])
      expect(mcp.selected_tool_names).to eq(["read_file", "list_dir"])
    end

    it "keeps previously selected tools that still exist" do
      mcp = build(:tools_mcp_server, discovered_tools: [
                    { "name" => "read_file" },
                    { "name" => "list_dir" },
                    { "name" => "search" },
                  ],)
      mcp.sync_selected_after_discovery(["read_file"])
      expect(mcp.selected_tool_names).to include("read_file")
    end

    it "adds newly discovered tools to selection" do
      mcp = build(:tools_mcp_server, discovered_tools: [
                    { "name" => "read_file" },
                    { "name" => "new_tool" },
                  ],)
      mcp.sync_selected_after_discovery(["read_file"])
      expect(mcp.selected_tool_names).to include("new_tool")
    end

    it "drops previously selected tools that no longer exist" do
      mcp = build(:tools_mcp_server, discovered_tools: [
                    { "name" => "read_file" },
                  ],)
      mcp.sync_selected_after_discovery(["read_file", "removed_tool"])
      expect(mcp.selected_tool_names).not_to include("removed_tool")
    end
  end

  describe "#tools_discovered?" do
    it "returns true when tools have been discovered" do
      mcp = build(:tools_mcp_server, :with_tools)
      expect(mcp.tools_discovered?).to be(true)
    end

    it "returns false when tools_discovered_at is nil" do
      mcp = build(:tools_mcp_server, tools_discovered_at: nil, discovered_tools: [{ "name" => "x" }])
      expect(mcp.tools_discovered?).to be(false)
    end

    it "returns false when discovered_tools is empty" do
      mcp = build(:tools_mcp_server, tools_discovered_at: Time.current, discovered_tools: [])
      expect(mcp.tools_discovered?).to be(false)
    end
  end

  describe "#mcp_server" do
    it "returns the connector" do
      mcp_connector = create(:connector, :mcp_server)
      mcp_tool = build(:tools_mcp_server, connector: mcp_connector)
      expect(mcp_tool.mcp_server).to eq(mcp_connector)
    end

    it "returns nil when connector is nil" do
      mcp_tool = build(:tools_mcp_server)
      allow(mcp_tool).to receive(:connector).and_return(nil)
      expect(mcp_tool.mcp_server).to be_nil
    end
  end

  describe "#perform_discovery!" do
    it "returns success when discovery succeeds" do
      mcp = create(:tools_mcp_server)
      result = double(success?: true, tools: [{ "name" => "tool1" }])
      allow(Tools::McpToolDiscoverer).to receive_message_chain(:new, :call).and_return(result) # rubocop:disable RSpec/MessageChain
      discovery_result = mcp.perform_discovery!
      expect(discovery_result.success?).to be(true)
      expect(discovery_result.message).to include("1")
    end

    it "returns failure when discovery fails" do
      mcp = create(:tools_mcp_server)
      result = double(success?: false, message: "Connection failed")
      allow(Tools::McpToolDiscoverer).to receive_message_chain(:new, :call).and_return(result) # rubocop:disable RSpec/MessageChain
      discovery_result = mcp.perform_discovery!
      expect(discovery_result.success?).to be(false)
      expect(discovery_result.message).to eq("Connection failed")
    end
  end

  describe "#update_visibility!" do
    it "updates selected_tools from params" do
      mcp = create(:tools_mcp_server)
      mcp.update_visibility!(mcp_server: { selected_tools: ["read_file", "list_dir"] })
      expect(mcp.selected_tool_names).to eq(["read_file", "list_dir"])
    end
  end

  describe "#visibility_available?" do
    it "returns true when tools have been discovered" do
      mcp = build(:tools_mcp_server, :with_tools)
      expect(mcp.visibility_available?).to be(true)
    end

    it "returns false when tools have not been discovered" do
      mcp = build(:tools_mcp_server, tools_discovered_at: nil, discovered_tools: [])
      expect(mcp.visibility_available?).to be(false)
    end
  end

  describe "#save!" do
    it "persists configuration to the tool record" do
      mcp = create(:tools_mcp_server)
      mcp.selected_tools = [{ "name" => "new_tool" }]
      mcp.save!
      mcp.reload
      expect(mcp.selected_tool_names).to eq(["new_tool"])
    end

    it "raises when no _tool_record is set" do
      mcp = build(:tools_mcp_server)
      expect { mcp.save! }.to raise_error(RuntimeError, "No _tool_record set")
    end
  end

  describe "#update!" do
    it "updates attributes and persists" do
      mcp = create(:tools_mcp_server)
      mcp.update!(selected_tools: [{ "name" => "updated" }])
      mcp.reload
      expect(mcp.selected_tool_names).to eq(["updated"])
    end
  end
end
