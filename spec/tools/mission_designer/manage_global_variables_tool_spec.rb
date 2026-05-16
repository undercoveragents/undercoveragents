# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ManageGlobalVariablesTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  describe "#name" do
    it "returns manage_global_variables" do
      expect(tool.name).to eq("manage_global_variables")
    end
  end

  describe "#execute with list action" do
    it "returns a clear message when mission context is missing" do
      tool_without_mission = described_class.new
      expected_message = [
        "Mission context is required before managing global variables.",
        "Create or open a mission first, or pass mission_id after creating a mission in the same turn.",
      ].join(" ")

      expect(tool_without_mission.execute(action: "list"))
        .to eq(expected_message)
    end

    it "lists another mission's globals when mission_id is provided" do
      other_mission = create(:mission, operation: mission.operation)
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: nil,
        tenant: mission.operation.tenant,
        operation: mission.operation,
      )
      target_tool = described_class.new(nil, runtime_context:)
      Missions::FlowEditor.new(other_mission).add_global_variable(key: "api_key", value: "secret", type: "string")

      result = target_tool.execute(action: "list", mission_id: other_mission.id)

      expect(result).to include("api_key")
      expect(result).to include("secret")
    end

    it "refuses to mutate Headquarter mission globals" do
      headquarter_mission = create(:mission, operation: mission.operation.tenant.headquarter_operation)
      runtime_context = BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission: nil,
        ui_context: nil,
        user: create(:user, :admin, tenant: mission.operation.tenant),
        tenant: mission.operation.tenant,
        operation: mission.operation.tenant.headquarter_operation,
      )

      result = described_class.new(nil, runtime_context:).execute(
        action: "add",
        mission_id: headquarter_mission.id,
        key: "api_key",
        value: "secret",
      )

      expect(result).to eq(ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
      expect(headquarter_mission.reload.flow_data["global_variables"]).to be_nil
    end

    it "returns empty message when no variables" do
      result = tool.execute(action: "list")
      expect(result).to include("No global variables defined")
    end

    it "lists defined variables" do
      Missions::FlowEditor.new(mission).add_global_variable(key: "api_key", value: "secret", type: "string")
      result = tool.execute(action: "list")
      expect(result).to include("api_key")
      expect(result).to include("secret")
      expect(result).to include("string")
      expect(result).to include("Globals are seeded inputs/constants only")
    end
  end

  describe "#execute with add action" do
    it "adds a global variable" do
      result = tool.execute(action: "add", key: "threshold", value: "0.8", type: "number")
      expect(result).to include("added")
      expect(result).to include("threshold")
      expect(result).to include("seeded inputs/constants")
    end

    it "returns error for duplicate key" do
      tool.execute(action: "add", key: "x", value: "1")
      result = tool.execute(action: "add", key: "x", value: "2")
      expect(result).to include("Error")
    end

    it "defaults type to string" do
      result = tool.execute(action: "add", key: "name", value: "test")
      expect(result).to include("string")
    end
  end

  describe "#execute with update action" do
    before { tool.execute(action: "add", key: "threshold", value: "0.5", type: "number") }

    it "updates value" do
      result = tool.execute(action: "update", key: "threshold", value: "0.9")
      expect(result).to include("updated")
      expect(result).to include("0.9")
    end

    it "returns error for nonexistent key" do
      result = tool.execute(action: "update", key: "missing", value: "x")
      expect(result).to include("Error")
    end
  end

  describe "#execute with remove action" do
    before { tool.execute(action: "add", key: "api_key", value: "secret") }

    it "removes the variable" do
      result = tool.execute(action: "remove", key: "api_key")
      expect(result).to include("removed")
      expect(result).to include("api_key")
    end

    it "returns error for nonexistent key" do
      result = tool.execute(action: "remove", key: "missing")
      expect(result).to include("Error")
    end
  end

  describe "#execute with unknown action" do
    it "returns error" do
      result = tool.execute(action: "unknown")
      expect(result).to include("Unknown action")
    end
  end

  describe "#execute when an unexpected error occurs" do
    it "rescues and returns an error message" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "unexpected failure")
      result = tool.execute(action: "list")
      expect(result).to include("Error managing global variables")
      expect(result).to include("unexpected failure")
    end
  end
end
