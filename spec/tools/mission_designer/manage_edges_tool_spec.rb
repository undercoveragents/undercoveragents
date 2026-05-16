# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ManageEdgesTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }
  let(:editor) { Missions::FlowEditor.new(mission) }

  let!(:node1_id) { editor.add_node(type: "llm")[:node][:id] }
  let!(:node2_id) { editor.add_node(type: "condition")[:node][:id] }

  describe "#name" do
    it "returns manage_edges" do
      expect(tool.name).to eq("manage_edges")
    end
  end

  describe "#execute with add action" do
    it "adds an edge between nodes" do
      result = tool.execute(action: "add", source_node_id: node1_id, target_node_id: node2_id)
      expect(result).to include("Edge added")
      expect(result).to include(node1_id)
      expect(result).to include(node2_id)
    end

    it "supports custom source port" do
      result = tool.execute(
        action: "add", source_node_id: node2_id, target_node_id: node1_id, source_port: "true",
      )
      expect(result).to include("true")
    end

    it "returns an error when a multi-port source omits source_port" do
      result = tool.execute(action: "add", source_node_id: node2_id, target_node_id: node1_id)

      expect(result).to include("Error")
      expect(result).to include("Source port is required")
    end

    it "returns error for nonexistent source" do
      result = tool.execute(action: "add", source_node_id: "bad", target_node_id: node2_id)
      expect(result).to include("Error")
    end
  end

  describe "#execute with remove action" do
    before do
      editor.add_edge(source_node_id: node1_id, target_node_id: node2_id)
    end

    it "removes an edge by source and target" do
      result = tool.execute(action: "remove", source_node_id: node1_id, target_node_id: node2_id)
      expect(result).to include("removed")
    end

    it "removes an edge by edge_id" do
      eid = mission.reload.flow_data["edges"].first["id"]
      result = tool.execute(action: "remove", source_node_id: node1_id, target_node_id: node2_id, edge_id: eid)
      expect(result).to include("removed")
    end

    it "returns error when no matching edge" do
      result = tool.execute(action: "remove", source_node_id: "bad", target_node_id: "bad")
      expect(result).to include("Error")
    end
  end

  describe "#execute with unknown action" do
    it "returns error" do
      result = tool.execute(action: "unknown", source_node_id: node1_id, target_node_id: node2_id)
      expect(result).to include("Unknown action")
    end
  end

  describe "error handling" do
    it "returns error message on unexpected failure" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute(action: "add", source_node_id: "a", target_node_id: "b")
      expect(result).to include("Error managing edge")
      expect(result).to include("boom")
    end
  end

  context "when the mission belongs to Headquarter" do
    let(:tenant) { create(:tenant) }
    let(:user) { create(:user, :admin, tenant:) }
    let(:mission) { create(:mission, operation: create(:operation, :headquarter, tenant:)) }
    let(:runtime_context) do
      BuiltinTools::RuntimeContext::Context.new(
        agent: nil,
        chat: nil,
        mission:,
        ui_context: nil,
        user:,
        tenant:,
        operation: mission.operation,
      )
    end
    let(:tool) { described_class.new(mission, runtime_context:) }

    it "refuses to mutate edges" do
      result = tool.execute(action: "add", source_node_id: node1_id, target_node_id: node2_id)

      expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
    end
  end
end
