# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentDesigner::CapabilityCatalog do
  describe ".render" do
    it "renders fields even when optional descriptions are omitted" do
      capability_class = Class.new do
        def self.agent_designer_fields
          [{ name: "memory_mode", type: "string", default: "ephemeral" }]
        end
      end
      capability_metadata = { key: "memory", label: "Memory", description: "Stores chat memory" }

      allow(CapabilityPlugin).to receive(:all_types).and_return([capability_metadata])
      allow(CapabilityPlugin).to receive(:resolve).with("memory").and_return(capability_class)

      result = described_class.render

      expect(result).to include("## Capabilities")
      expect(result).to include("- `memory` — Memory — Stores chat memory")
      expect(result).to include("  - `memory_mode` (string) — default=`ephemeral`")
    end
  end
end
