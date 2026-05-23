# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigateToPageTool do
  let(:tenant) { Tenant.default_tenant.tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:mission) { create(:mission, operation:) }
  let(:client_channel) do
    create(:channel, :client, tenant:, name: "Support Portal").tap do |channel|
      create(:channel_target, channel:, target: create(:agent, operation:, model_id: "gpt-4.1"), default: true)
    end
  end
  let(:tool_record) do
    connector = create(:connector, :mcp_server, tenant:)
    create(:tool, operation:, name: "Filesystem MCP", toolable: Tools::McpServer.new(connector_id: connector.id))
  end
  let(:test_suite) { create(:test_suite, agent: create(:agent, operation:, model_id: "gpt-4.1")) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:tool) { described_class.new(parent_chat: chat, mission:) }

  describe "metadata" do
    it "exposes the runtime name and description", :aggregate_failures do
      expect(tool.name).to eq("navigate_to_page")
      expect(tool.description).to eq(described_class::DESCRIPTION)
    end
  end

  describe "private helpers" do
    it "returns the shared-chat requirement when no application chat is present" do
      expect(described_class.new.send(:navigation_message, false)).to eq(
        "Navigation is only broadcast from the shared application chat, and it never returns page contents.",
      )
    end
  end

  describe "#execute" do
    it "broadcasts a Turbo navigation payload for a mission page" do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(resource: "mission", page: "designer", record_id: mission.id)

      expect(result).to include("Navigation target resolved for UI handoff only.")
      expect(result).to include("No page content or record data is returned by this tool.")
      expect(result).to include("This only points the UI to the page; the next turn will use the new page context.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "navigate",
          chat_id: chat.id,
          path: Rails.application.routes.url_helpers.designer_admin_mission_path(mission),
        ),
      )
    end

    it "rejects unsupported pages" do
      result = tool.execute(resource: "mission", page: "show", record_id: mission.id)

      expect(result).to eq("Error: Unknown page 'show' for mission. Use index, new, edit, or designer.")
    end

    it "returns a manual path when navigation was skipped in the shared application chat" do
      allow(RuntimeRecords::Navigation).to receive(:broadcast!).and_return(:skipped)

      result = tool.execute(resource: "mission", page: "designer", record_id: mission.id)

      expect(result).to include("Navigation was not broadcast.")
    end

    it "reports navigation availability outside the shared application chat" do
      non_application_chat = create(:chat, user:)
      allow(non_application_chat).to receive(:application?).and_return(false)
      allow(RuntimeRecords::Navigation).to receive(:broadcast!).and_return(:skipped)
      non_application_tool = described_class.new(parent_chat: non_application_chat, mission:)

      result = non_application_tool.execute(resource: "mission", page: "designer", record_id: mission.id)

      expect(result).to include(
        "Navigation is only broadcast from the shared application chat, and it never returns page contents.",
      )
    end

    it "reports missing records" do
      result = tool.execute(resource: "mission", page: "designer", record_id: "missing")

      expect(result).to eq("Error: Mission 'missing' was not found.")
    end

    it "broadcasts a Turbo navigation payload for a tool page" do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(resource: "tool", page: "edit", record_id: tool_record.id)

      expect(result).to include("Navigation target resolved for UI handoff only.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "navigate",
          chat_id: chat.id,
          path: Rails.application.routes.url_helpers.edit_admin_tool_path(tool_record),
        ),
      )
    end

    it "broadcasts a Turbo navigation payload for a test suite page" do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(resource: "test_suite", page: "edit", record_id: test_suite.id)

      expect(result).to include("Navigation target resolved for UI handoff only.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "navigate",
          chat_id: chat.id,
          path: Rails.application.routes.url_helpers.edit_admin_test_suite_path(test_suite),
        ),
      )
    end

    it "broadcasts a Turbo navigation payload for an agent prompt preview page" do
      allow(ActionCable.server).to receive(:broadcast)
      agent = create(:agent, operation:, model_id: "gpt-4.1")

      result = tool.execute(resource: "agent", page: "prompt_preview", record_id: agent.id)

      expect(result).to include("Navigation target resolved for UI handoff only.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "navigate",
          chat_id: chat.id,
          path: Rails.application.routes.url_helpers.prompt_preview_admin_agent_path(agent),
        ),
      )
    end

    it "broadcasts a Turbo navigation payload for a client-channel preview page" do
      allow(ActionCable.server).to receive(:broadcast)

      result = tool.execute(resource: "channel", page: "preview", record_id: client_channel.id)

      expect(result).to include("Navigation target resolved for UI handoff only.")
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(
          type: "navigate",
          chat_id: chat.id,
          path: Rails.application.routes.url_helpers.admin_channel_path(client_channel, view: :preview),
        ),
      )
    end

    it "returns unexpected navigation errors with context" do
      broken_manager = instance_double(RuntimeRecords::Manager)
      allow(RuntimeRecords::Manager).to receive(:new).and_return(broken_manager)
      allow(broken_manager).to receive(:navigation_path).and_raise(StandardError, "boom")

      result = tool.execute(resource: "mission", page: "designer", record_id: mission.id)

      expect(result).to eq("Failed to navigate: boom")
    end
  end
end
