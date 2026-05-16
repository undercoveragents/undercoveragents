# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ModelsController do
  describe "#facet_options" do
    it "ignores blank facet values and sorts remaining options by count then name" do
      create(:model, capabilities: ["streaming", ""])
      create(:model, capabilities: ["streaming", "analysis"])

      options = controller.send(:facet_options, Model.all, :capability)

      expect(options).to eq([
                              { value: "streaming", count: 2 },
                              { value: "analysis", count: 1 },
                            ])
    end
  end

  describe "#facet_values_for" do
    it "returns an empty array for unsupported facet keys" do
      expect(controller.send(:facet_values_for, build(:model), :unsupported)).to eq([])
    end

    it "returns output modalities for the output_modality facet" do
      model = build(:model, modalities: { "output" => ["image", "text"] })

      expect(controller.send(:facet_values_for, model, :output_modality)).to eq(["image", "text"])
    end
  end

  describe "#modalities_for" do
    it "returns an empty array when modalities are not stored as a hash" do
      model = build(:model, modalities: ["image"])

      expect(controller.send(:modalities_for, model, "output")).to eq([])
    end
  end

  describe "#apply_json_array_filter" do
    it "returns the original scope for unsupported filter keys" do
      scope = Model.all

      expect(controller.send(:apply_json_array_filter, scope, :unsupported, "text")).to eq(scope)
    end
  end

  describe "#apply_sort" do
    it "does not append a duplicate model_id sort when model_id is already the primary column" do
      scope = instance_double(ActiveRecord::Relation)
      ordered_scope = instance_spy(ActiveRecord::Relation)

      allow(controller).to receive_messages(sort_column: "model_id", sort_direction: "asc")
      allow(scope).to receive(:order).with("model_id" => :asc).and_return(ordered_scope)
      allow(ordered_scope).to receive(:order).with(provider: :asc).and_return(ordered_scope)

      controller.send(:apply_sort, scope)

      expect(ordered_scope).not_to have_received(:order).with(model_id: :asc)
    end
  end
end
