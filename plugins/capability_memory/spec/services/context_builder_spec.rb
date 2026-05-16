# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::Memory::ContextBuilder do
  subject(:builder) { described_class.new(agent, user:) }

  let(:agent) { create(:agent) }
  let(:user)  { create(:user) }

  describe "#build" do
    context "when the user has no memory blocks" do
      it "returns nil" do
        expect(builder.build).to be_nil
      end
    end

    context "when the user has memory blocks" do
      before do
        persona_block = create(:memory_block, label: "persona", description: "Agent persona",
                                              default_value: "I am helpful.",)
        human_block   = create(:memory_block, label: "human", description: "User info",
                                              default_value: "Likes concise answers.",)
        create(:agent_memory_block, agent:, memory_block: persona_block, user:,
                                    value: "I am helpful.",)
        create(:agent_memory_block, agent:, memory_block: human_block, user:,
                                    value: "Likes concise answers.",)
      end

      it "returns an XML envelope wrapping all blocks" do
        xml = builder.build

        expect(xml).to start_with("<memory_blocks>")
        expect(xml).to end_with("</memory_blocks>")
      end

      it "includes persona block XML" do
        xml = builder.build

        expect(xml).to include("<persona>")
        expect(xml).to include("</persona>")
        expect(xml).to include("I am helpful.")
      end

      it "includes human block XML" do
        xml = builder.build

        expect(xml).to include("<human>")
        expect(xml).to include("</human>")
        expect(xml).to include("Likes concise answers.")
      end
    end

    context "when user is nil" do
      subject(:builder) { described_class.new(agent, user: nil) }

      it "returns nil" do
        expect(builder.build).to be_nil
      end
    end
  end
end
