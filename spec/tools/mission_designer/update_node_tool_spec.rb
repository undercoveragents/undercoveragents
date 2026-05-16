# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::UpdateNodeTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }
  let(:editor) { Missions::FlowEditor.new(mission) }

  describe "#name" do
    it "returns update_node" do
      expect(tool.name).to eq("update_node")
    end
  end

  describe "#execute" do
    let!(:node_id) { editor.add_node(type: "llm", name: "Test")[:node][:id] }

    it "updates node config from a JSON string" do
      result = tool.execute(id: node_id, config: '{"prompt": "New prompt"}')
      expect(result).to include("updated successfully")
    end

    it "updates node config when LLM sends config as a Hash object instead of JSON string" do
      result = tool.execute(id: node_id, config: { "prompt" => "New prompt" })
      expect(result).to include("updated successfully")
    end

    it "sets selected_variables on an output node via Hash config" do
      output_id = editor.add_node(type: "output", name: "Output")[:node][:id]
      result = tool.execute(
        id: output_id,
        config: { "selected_variables" => ["my_llm.response", "my_llm.score"] },
      )
      expect(result).to include("updated successfully")
      updated_node = mission.reload.flow_data["nodes"].find { |n| n["id"] == output_id }
      expect(updated_node["data"]["selected_variables"]).to eq(["my_llm.response", "my_llm.score"])
    end

    it "updates node name" do
      result = tool.execute(id: node_id, name: "New Name")
      expect(result).to include("updated successfully")
      expect(result).to include("New Name")
    end

    it "returns error for unknown node" do
      result = tool.execute(id: "bad-id", config: '{"prompt": "test"}')
      expect(result).to include("Error")
      expect(result).to include("Node not found")
    end

    it "returns error for invalid JSON" do
      result = tool.execute(id: node_id, config: "{bad")
      expect(result).to include("Invalid config JSON")
    end

    it "returns error when no changes specified" do
      result = tool.execute(id: node_id)
      expect(result).to include("No changes specified")
    end

    it "returns error message on unexpected failure" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute(id: "any-id", config: '{"x": 1}')
      expect(result).to include("Error updating node")
      expect(result).to include("boom")
    end

    it "omits the variable prefix when the updated node does not expose one" do
      message = tool.send(:format_update_result, {
                            id: "node-123",
                            name: "Plain Node",
                            type: "text_template",
                            variable_name: nil,
                          })

      expect(message).to eq("Node `node-123` updated successfully (Plain Node, type: text_template).")
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

      it "refuses to update nodes" do
        result = tool.execute(id: node_id, config: { "prompt" => "Blocked" })

        expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      end
    end
  end
end
