# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ExpressionReferenceTool do
  let(:tool) { described_class.new }

  describe "#name" do
    it "returns get_expression_reference" do
      expect(tool.name).to eq("get_expression_reference")
    end
  end

  describe "#execute" do
    it "returns the full expression reference" do
      expect(tool.execute).to eq(Missions::ExpressionDocs::FULL_REFERENCE)
    end
  end
end
