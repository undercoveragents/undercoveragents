# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpServerTool do
  let(:connector) { create(:connector, :mcp_server, :enabled) }

  let(:mcp_tool_record) do
    create(:tools_mcp_server, :with_tools, connector:)
  end

  let(:tool_record) do
    create(:tool, :enabled, name: "MCP Tools", toolable: mcp_tool_record)
  end

  let(:mock_read_tool) { instance_double(RubyLLM::MCP::Tool, name: "read_file") }
  let(:mock_list_tool) { instance_double(RubyLLM::MCP::Tool, name: "list_directory") }
  let(:mock_search_tool) { instance_double(RubyLLM::MCP::Tool, name: "search_files") }
  let(:mock_client) do
    # rubocop:disable RSpec/VerifiedDoubleReference
    instance_double("RubyLLM::MCP::Client", tools: [mock_read_tool, mock_list_tool, mock_search_tool])
    # rubocop:enable RSpec/VerifiedDoubleReference
  end

  before do
    allow(connector).to receive(:build_client_config).and_return({ name: "test" })
    allow(RubyLLM::MCP).to receive(:client).and_return(mock_client)
  end

  describe ".for_tool" do
    it "returns an array of MCP tools" do
      tools = described_class.for_tool(tool_record)
      expect(tools).to be_an(Array)
      expect(tools.size).to eq(3)
    end

    it "filters to selected tools only" do
      mcp_tool_record.update!(selected_tools: [{ "name" => "read_file" }])
      tools = described_class.for_tool(tool_record)
      expect(tools).to eq([mock_read_tool])
    end

    it "returns all tools when no selection is made" do
      mcp_tool_record.update!(selected_tools: [])
      tools = described_class.for_tool(tool_record)
      expect(tools.size).to eq(3)
    end

    it "raises for non-MCP Server tools" do
      sql_tool = build(:tool, :sql_query)
      expect do
        described_class.for_tool(sql_tool)
      end.to raise_error(ArgumentError, /MCP Server tool/)
    end

    context "when an error occurs" do
      before do
        allow(RubyLLM::MCP).to receive(:client).and_raise(StandardError, "Connection failed")
        allow(Rails.logger).to receive(:error)
      end

      it "returns an empty array" do
        tools = described_class.for_tool(tool_record)
        expect(tools).to eq([])
      end

      it "logs the error" do
        described_class.for_tool(tool_record)
        expect(Rails.logger).to have_received(:error).with(/Failed to resolve tools/)
      end
    end

    context "when mcp_server is nil" do
      before { allow(mcp_tool_record).to receive(:mcp_server).and_return(nil) }

      it "returns an empty array" do
        tools = described_class.for_tool(tool_record)
        expect(tools).to eq([])
      end
    end
  end
end
