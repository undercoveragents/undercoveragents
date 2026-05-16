# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::McpToolDiscoverer do
  let(:mcp_connector) { create(:connector, :mcp_server) }

  describe "#call" do
    context "when discovery succeeds" do
      let(:mock_read_tool) { instance_double(RubyLLM::MCP::Tool, name: "read_file", description: "Read a file") }
      let(:mock_list_tool) { instance_double(RubyLLM::MCP::Tool, name: "list_dir", description: "List directory") }
      let(:mock_client) do
        # rubocop:disable RSpec/VerifiedDoubleReference
        instance_double("RubyLLM::MCP::Client", tools: [mock_read_tool, mock_list_tool], stop: nil)
        # rubocop:enable RSpec/VerifiedDoubleReference
      end

      before do
        allow(mcp_connector).to receive(:build_client_config).and_return({ name: "test" })
        allow(RubyLLM::MCP).to receive(:client).and_return(mock_client)
      end

      it "returns a successful result" do
        result = described_class.new(mcp_connector).call
        expect(result.success?).to be(true)
      end

      it "returns the discovered tools" do
        result = described_class.new(mcp_connector).call
        expect(result.tools).to eq([
                                     { "name" => "read_file", "description" => "Read a file" },
                                     { "name" => "list_dir", "description" => "List directory" },
                                   ])
      end

      it "includes a count message" do
        result = described_class.new(mcp_connector).call
        expect(result.message).to eq("Discovered 2 tool(s)")
      end

      it "stops the MCP client after discovery" do
        described_class.new(mcp_connector).call
        expect(mock_client).to have_received(:stop)
      end

      it "ignores client stop failures" do
        allow(mock_client).to receive(:stop).and_raise(StandardError, "stop failed")

        expect { described_class.new(mcp_connector).send(:stop_client, mock_client) }.not_to raise_error
      end
    end

    context "when a transport error occurs" do
      before do
        allow(mcp_connector).to receive(:build_client_config).and_return({ name: "test" })
        allow(RubyLLM::MCP).to receive(:client)
          .and_raise(RubyLLM::MCP::Errors::TransportError.new(message: "Connection refused"))
      end

      it "returns a failure result" do
        result = described_class.new(mcp_connector).call
        expect(result.success?).to be(false)
      end

      it "includes the transport error message" do
        result = described_class.new(mcp_connector).call
        expect(result.message).to include("Transport error")
      end

      it "returns empty tools" do
        result = described_class.new(mcp_connector).call
        expect(result.tools).to eq([])
      end
    end

    context "when a timeout error occurs" do
      before do
        allow(mcp_connector).to receive(:build_client_config).and_return({ name: "test" })
        allow(RubyLLM::MCP).to receive(:client)
          .and_raise(RubyLLM::MCP::Errors::TimeoutError.new(message: "Timed out"))
      end

      it "returns a failure result" do
        result = described_class.new(mcp_connector).call
        expect(result.success?).to be(false)
        expect(result.message).to include("timed out")
      end
    end

    context "when a standard error occurs" do
      before do
        allow(mcp_connector).to receive(:build_client_config).and_return({ name: "test" })
        allow(RubyLLM::MCP).to receive(:client)
          .and_raise(StandardError, "Something went wrong")
      end

      it "returns a failure result" do
        result = described_class.new(mcp_connector).call
        expect(result.success?).to be(false)
        expect(result.message).to include("Something went wrong")
      end
    end
  end
end
