# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::MissionFlowsController do
  describe "#singleton_node?" do
    it "returns false when the node type has no metadata" do
      allow(MissionNodePlugin).to receive(:metadata_for).with("unknown_type").and_return(nil)

      expect(controller.send(:singleton_node?, "unknown_type", { "nodes" => [] })).to be(false)
    end
  end
end
