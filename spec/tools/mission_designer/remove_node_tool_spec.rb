# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::RemoveNodeTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }
  let(:editor) { Missions::FlowEditor.new(mission) }

  describe "#name" do
    it "returns remove_node" do
      expect(tool.name).to eq("remove_node")
    end
  end

  describe "#execute" do
    it "removes an existing node" do
      node_id = editor.add_node(type: "llm", name: "ToRemove")[:node][:id]
      result = tool.execute(node_id:)
      expect(result).to include("removed")
      expect(result).to include("ToRemove")
    end

    it "returns error for unknown node" do
      result = tool.execute(node_id: "bad-id")
      expect(result).to include("Error")
      expect(result).to include("Node not found")
    end

    it "returns error message on unexpected failure" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute(node_id: "any-id")
      expect(result).to include("Error removing node")
      expect(result).to include("boom")
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

      it "refuses to remove nodes" do
        node_id = editor.add_node(type: "llm", name: "Keep Me")[:node][:id]
        result = tool.execute(node_id:)

        expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      end
    end
  end
end
