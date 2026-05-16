# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::ArrangeFlowTool do
  let(:mission) { create(:mission) }
  let(:tool) { described_class.new(mission) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
  end

  describe "#name" do
    it "returns arrange_flow" do
      expect(tool.name).to eq("arrange_flow")
    end
  end

  describe "#execute" do
    it "returns a success message" do
      result = tool.execute
      expect(result).to include("arranged")
    end

    it "broadcasts arrange signal to the mission flow channel" do
      tool.execute
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with("mission_flow_#{mission.id}", hash_including(target: "mission-flow-updates"))
    end

    it "includes data-arrange attribute in the broadcast html" do
      tool.execute
      expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
        .with(anything, hash_including(html: include("data-arrange")))
    end

    it "returns error message on failure" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, "boom")
      result = tool.execute
      expect(result).to include("Error arranging flow")
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

      it "refuses to broadcast layout changes" do
        result = tool.execute

        expect(result).to eq("Error: #{ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE}")
        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
      end
    end
  end
end
