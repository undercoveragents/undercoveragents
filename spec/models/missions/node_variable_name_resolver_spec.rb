# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::NodeVariableNameResolver do
  describe ".build_map" do
    it "returns an empty map when flow_data is nil" do
      expect(described_class.build_map(nil)).to eq({})
    end

    it "skips nodes whose derived base name is blank" do
      flow_data = {
        "nodes" => [
          { "id" => nil, "type" => "llm", "data" => { "label" => " ", "name" => nil } },
        ],
      }

      expect(described_class.build_map(flow_data)).to eq({})
    end
  end

  describe ".assign!" do
    it "returns nil when flow_data is nil" do
      expect(described_class.assign!(nil)).to be_nil
    end

    it "removes stale names when a node no longer has a usable prefix" do
      flow_data = {
        "nodes" => [
          { "id" => nil, "type" => "llm", "data" => { "label" => " ", "name" => " " } },
        ],
      }

      described_class.assign!(flow_data)

      expect(flow_data.dig("nodes", 0, "data")).not_to have_key("name")
    end
  end
end
