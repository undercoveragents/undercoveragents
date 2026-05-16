# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::RuntimeContextInstructions do
  describe "#build" do
    let(:detailed_ui_context) do
      {
        ui_context: {
          page: {
            name: "Mission details",
            controller: "admin/missions",
            action: "designer",
            path: "/admin/missions/1/designer",
            params: {
              stage: "embedding",
              operation: "default",
            },
          },
          current_object: {
            type: "Mission",
            label: "Policy Mission",
            slug: "policy-mission",
            id: 1,
          },
          operation: {
            name: "Default",
            slug: "default",
          },
          references: [
            123,
            { type: "Mission", label: "Policy Mission", id: 5, slug: "policy-mission", mention: "#mission" },
            { label: "Stage selector" },
          ],
          reference_trigger: "#",
        },
      }
    end

    it "returns an empty string when ui_context is missing" do
      expect(described_class.new({}).build).to eq("")
    end

    it "renders page params and filters non-hash references" do
      rendered = described_class.new(detailed_ui_context).build

      expect(rendered).to include(
        "Visible page params: stage=embedding, operation=default",
        "Current object: Mission: Policy Mission | slug: policy-mission | id: 1",
        "Selected references: Mission: Policy Mission | id: 5 | slug: policy-mission | mention: #mission, " \
        "Stage selector",
      )
    end

    it "falls back to the object type when no object details are available" do
      rendered = described_class.new(
        ui_context: {
          current_object: { type: "Connector" },
          references: [123],
          reference_trigger: "#",
        },
      ).build

      expect(rendered).to include(
        "Current object: Connector",
        "Selected references: none",
      )
    end

    it "skips non-hash objects and renders operations without slugs" do
      rendered = described_class.new(
        ui_context: {
          current_object: "Connector",
          operation: { name: "Default" },
          references: [],
          reference_trigger: "#",
        },
      ).build

      expect(rendered).to include("Current operation: Default")
      expect(rendered).not_to include("Current object:")
    end
  end
end
