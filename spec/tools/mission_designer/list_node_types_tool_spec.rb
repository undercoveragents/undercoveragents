# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ListNodeTypesTool do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns list_node_types" do
      expect(tool.name).to eq("list_node_types")
    end
  end

  describe "#execute" do
    it "returns all registered node types" do
      result = tool.execute
      expect(result).to include("Available Node Types")
      expect(result).to include("`llm`")
      expect(result).to include("`condition`")
      expect(result).to include("`iterator`")
    end

    it "groups by category" do
      result = tool.execute
      expect(result).to include("Node")
      expect(result).to include("Control")
    end

    it "returns error message on unexpected failure" do
      allow(MissionNodePlugin).to receive(:all_types).and_raise(StandardError, "boom")
      result = tool.execute
      expect(result).to include("Error listing node types")
      expect(result).to include("boom")
    end
  end
end
