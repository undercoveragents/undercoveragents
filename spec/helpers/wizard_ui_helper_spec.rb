# frozen_string_literal: true

require "rails_helper"

RSpec.describe WizardUiHelper do
  describe "#build_wizard_component" do
    it "builds steps with default numbering" do
      wizard = helper.build_wizard_component(
        eyebrow: "SQL Source",
        title: "Configure ingestion",
        subtitle: "Pick a connector and source.",
        steps: [
          { label: "Connect", target_id: "step-connect" },
          { label: "Choose source", target_id: "step-source" },
        ],
      )

      expect(wizard).to have_attributes(
        eyebrow: "SQL Source",
        title: "Configure ingestion",
        subtitle: "Pick a connector and source.",
      )
      expect(wizard.steps.map(&:number)).to eq(["1", "2"])
      expect(wizard.steps.map(&:label)).to eq(["Connect", "Choose source"])
      expect(wizard.steps.map(&:target_id)).to eq(["step-connect", "step-source"])
    end

    it "preserves explicit numbering and normalizes blank optional copy" do
      wizard = helper.build_wizard_component(
        eyebrow: "",
        title: "Configure ingestion",
        subtitle: " ",
        steps: [
          { number: 7, label: "Review", target_id: "step-review" },
        ],
      )

      expect(wizard.eyebrow).to be_nil
      expect(wizard.subtitle).to be_nil
      expect(wizard.steps.first).to have_attributes(
        number: "7",
        label: "Review",
        target_id: "step-review",
      )
    end
  end
end
