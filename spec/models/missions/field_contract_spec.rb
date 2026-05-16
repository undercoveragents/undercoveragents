# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FieldContract do
  describe "#initialize" do
    it "normalizes values and exposes predicates", :aggregate_failures do
      contract = described_class.new(
        key: :prompt,
        kind: :template,
        value_type: :string,
        description: "Prompt",
        required: true,
        json: false,
      )

      expect(contract.key).to eq("prompt")
      expect(contract.kind).to eq(:template)
      expect(contract.value_type).to eq(:string)
      expect(contract.description).to eq("Prompt")
      expect(contract).to be_required
      expect(contract).to be_template
      expect(contract).to be_reference_scannable
      expect(contract).not_to be_json
    end

    it "raises for an unknown kind" do
      expect do
        described_class.new(key: "prompt", kind: :mystery)
      end.to raise_error(ArgumentError, /Unknown field contract kind/)
    end

    it "exposes the input_fields predicate" do
      contract = described_class.new(key: "fields", kind: :input_fields)

      expect(contract).to be_input_fields
    end
  end
end
