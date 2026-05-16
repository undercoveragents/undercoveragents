# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::AddNodeTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  describe "#name" do
    it "returns add_node" do
      expect(tool.name).to eq("add_node")
    end
  end

  describe "#execute" do
    it "adds a node successfully" do
      result = tool.execute(node_type: "llm", name: "Test LLM")
      expect(result).to include("added successfully")
      expect(result).to include("node-")
    end

    it "adds a node with config" do
      result = tool.execute(
        node_type: "llm",
        config: '{"prompt": "Summarize this", "connector_id": "1"}',
      )
      expect(result).to include("added successfully")
    end

    it "returns error for unknown type" do
      result = tool.execute(node_type: "nonexistent")
      expect(result).to include("Error")
      expect(result).to include("Unknown node type")
    end

    it "returns error for invalid JSON config" do
      result = tool.execute(node_type: "llm", config: "{bad json")
      expect(result).to include("Invalid config JSON")
    end

    it "adds a node with config as a Hash object (LLM may send object instead of JSON string)" do
      result = tool.execute(
        node_type: "llm",
        config: { "prompt" => "Summarize this", "connector_id" => "1" },
      )
      expect(result).to include("added successfully")
    end

    it "handles nil config gracefully" do
      result = tool.execute(node_type: "llm")
      expect(result).to include("added successfully")
    end

    it "includes port info for branching node types" do
      result = tool.execute(node_type: "condition", config: '{"expression": "x > 5"}')
      expect(result).to include("Available ports")
      expect(result).to include("`true`")
      expect(result).to include("`false`")
    end

    it "includes validation hint when required fields are missing" do
      result = tool.execute(node_type: "llm", config: '{"llm_config_source":"node"}')
      expect(result).to include("validation issue")
    end

    it "omits available ports when a branching node type cannot be resolved" do
      allow(MissionNodePlugin).to receive(:resolve).with("condition").and_return(nil)

      expect(tool.send(:format_ports, "condition")).to eq("")
    end

    it "does not include validation hint when flow is valid and clean" do
      result = tool.execute(node_type: "set_variable", config: '{"assignments": {"x": "1"}}')
      expect(result).not_to include("validation issue")
    end

    it "returns error message on unexpected failure" do
      allow(Missions::FlowEditor).to receive(:new).and_raise(StandardError, "boom")
      result = tool.execute(node_type: "llm")
      expect(result).to include("Error adding node")
      expect(result).to include("boom")
    end

    context "with near_node_id" do
      let(:editor) { Missions::FlowEditor.new(mission) }
      let!(:upstream_id) { editor.add_node(type: "llm", name: "Upstream")[:node][:id] }

      it "places new node near the referenced node" do
        result = tool.execute(node_type: "condition", name: "Nearby", near_node_id: upstream_id,
                              config: '{"expression": "x > 1"}',)
        expect(result).to include("added successfully")
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

      it "refuses to add nodes" do
        result = tool.execute(node_type: "input")

        expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
      end
    end
  end
end
