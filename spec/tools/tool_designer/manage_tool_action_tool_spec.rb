# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::ManageToolActionTool do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:user) { create(:user, :admin, tenant:) }
  let(:chat) { create(:chat, :application_context, user:) }
  let(:connector) { create(:connector, :sql_database, tenant:) }
  let(:tool_path) { Rails.application.routes.url_helpers.admin_tool_path(tool_record) }
  let(:tool_record) do
    create(
      :tool,
      :enabled,
      operation:,
      name: "Orders Explorer",
      toolable: Tools::SqlQuery.new(
        connector_id: connector.id,
        llm_config_source: "inherit",
        discovered_schema: {
          "objects" => [
            { "name" => "users", "columns" => [{ "name" => "id" }] },
            { "name" => "orders", "columns" => [{ "name" => "id" }] },
          ],
        },
        schema_discovered_at: Time.current,
        selected_objects: [{ "name" => "users" }, { "name" => "orders" }],
      ),
    )
  end
  let(:ui_context) do
    {
      "page" => { "path" => tool_path, "action" => "show" },
      "current_object" => { "class_name" => "Tool", "id" => tool_record.id },
    }
  end
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat:,
      mission: nil,
      ui_context:,
      user:,
      tenant:,
      operation:,
    )
  end

  describe "#execute" do
    it "updates visibility and broadcasts a refresh", :aggregate_failures do
      allow(ActionCable.server).to receive(:broadcast)

      result = described_class.new(runtime_context:, current_tool: tool_record)
                              .execute(action: "set_visibility", selected_items: ["users"])

      expect(result).to include("Tool action completed.")
      expect(result).to include("Current page refresh started")
      expect(tool_record.reload.toolable.selected_object_names).to eq(["users"])
      expect(ActionCable.server).to have_received(:broadcast).with(
        chat.ui_stream_channel_name,
        hash_including(type: "refresh", chat_id: chat.id, path: tool_path),
      )
    end

    it "returns plugin action errors" do
      allow(tool_record.toolable).to receive(:perform_discovery!)
        .and_return(ToolPlugin::Result.new(success?: false, message: "Connection refused"))

      result = described_class.new(runtime_context:, current_tool: tool_record)
                              .execute(action: "discover")

      expect(result).to eq("Error: Connection refused")
    end

    it "omits the refresh message when no refresh is broadcast" do
      allow(RuntimeRecords::Refresh).to receive(:broadcast!).and_return(:skipped)

      result = described_class.new(runtime_context:, current_tool: tool_record)
                              .execute(action: "set_visibility", selected_items: ["users"])

      expect(result).to include("Tool action completed.")
      expect(result).not_to include("Current page refresh started")
    end

    it "refuses to mutate Headquarter tools" do
      headquarter_tool = create(
        :tool,
        :enabled,
        operation: tenant.headquarter_operation,
        name: "Headquarter Explorer",
        toolable: Tools::SqlQuery.new(
          connector_id: connector.id,
          llm_config_source: "inherit",
          discovered_schema: tool_record.toolable.discovered_schema,
          schema_discovered_at: Time.current,
          selected_objects: [{ "name" => "users" }],
        ),
      )

      result = described_class.new(runtime_context:, current_tool: headquarter_tool)
                              .execute(action: "set_visibility", selected_items: ["orders"])

      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      expect(headquarter_tool.reload.toolable.selected_object_names).to eq(["users"])
    end

    it "returns a helpful message when there is no current tool" do
      result = described_class.new(runtime_context:).execute(action: "discover")

      expect(result).to eq(
        "No current tool is available. Pass tool_id after creating one or open a tool page first.",
      )
    end

    it "returns argument errors from invalid actions" do
      result = described_class.new(runtime_context:, current_tool: tool_record).execute(action: "unknown")

      expect(result).to eq(
        "Error: Action 'unknown' is not supported for SQL Query. " \
        "Use discover, set_visibility.",
      )
    end

    it "rescues unexpected errors from the action manager" do
      manager = instance_double(Tools::AdminManager)
      allow(Tools::AdminManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:perform_action!).and_raise(StandardError, "boom")

      result = described_class.new(runtime_context:, current_tool: tool_record).execute(action: "discover")

      expect(result).to eq("Error managing tool action: boom")
    end
  end
end
