# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModelsHelper do
  describe "#models_query_params" do
    it "keeps known query params and applies overrides" do
      allow(helper).to receive(:request).and_return(
        instance_double(
          ActionDispatch::Request,
          query_parameters: {
            "provider" => "openai",
            "sort" => "provider",
            "direction" => "asc",
            "ignored" => "value",
          },
        ),
      )

      expect(helper.models_query_params(provider: "anthropic", page: nil)).to eq(
        "provider" => "anthropic",
        "sort" => "provider",
        "direction" => "asc",
      )
    end
  end

  describe "#models_filters_active?" do
    it "returns false when only sorting params are present" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(sort: "provider", direction: "asc"))

      expect(helper.models_filters_active?).to be(false)
    end

    it "returns true when a filter param is present" do
      allow(helper).to receive(:params).and_return(ActionController::Parameters.new(provider: "openai"))

      expect(helper.models_filters_active?).to be(true)
    end
  end

  describe "#models_next_sort_direction" do
    it "toggles to descending for the active ascending column" do
      expect(
        helper.models_next_sort_direction("provider", current_sort: "provider", current_direction: "asc"),
      ).to eq("desc")
    end

    it "defaults to ascending for a different column" do
      expect(
        helper.models_next_sort_direction("name", current_sort: "provider", current_direction: "desc"),
      ).to eq("asc")
    end
  end

  describe "#models_sort_icon" do
    it "returns a neutral icon for inactive columns" do
      expect(
        helper.models_sort_icon("provider", current_sort: "name", current_direction: "asc"),
      ).to eq("fa-solid fa-sort text-text-muted")
    end

    it "returns an ascending icon for active ascending columns" do
      expect(
        helper.models_sort_icon("provider", current_sort: "provider", current_direction: "asc"),
      ).to eq("fa-solid fa-sort-up")
    end

    it "returns a descending icon for active descending columns" do
      expect(
        helper.models_sort_icon("provider", current_sort: "provider", current_direction: "desc"),
      ).to eq("fa-solid fa-sort-down")
    end
  end

  describe "#models_table_value" do
    it "returns a dash for blank values" do
      expect(helper.models_table_value(nil)).to eq("—")
      expect(helper.models_table_value("")).to eq("—")
    end

    it "returns the original value when present" do
      expect(helper.models_table_value("openai")).to eq("openai")
    end
  end

  describe "#model_capabilities" do
    it "returns compact capabilities" do
      model_record = build(:model, capabilities: ["streaming", nil, "vision"])

      expect(helper.model_capabilities(model_record)).to eq(["streaming", "vision"])
    end
  end

  describe "#model_inline_values" do
    it "joins values into a single line" do
      expect(helper.model_inline_values(["text", "image", "audio"])).to eq("text, image, audio")
    end

    it "returns a dash when values are blank" do
      expect(helper.model_inline_values([nil, ""])).to eq("—")
    end
  end

  describe "#model_modalities" do
    it "returns modalities for the selected key" do
      model_record = build(:model, modalities: { "input" => ["text"], "output" => ["audio"] })

      expect(helper.model_modalities(model_record, "output")).to eq(["audio"])
    end

    it "returns an empty array when modalities are not a hash" do
      model_record = build(:model, modalities: nil)

      expect(helper.model_modalities(model_record, "output")).to eq([])
    end
  end

  describe "#model_price_value" do
    it "formats pricing values from the text token pricing block" do
      model_record = build(:model)

      expect(helper.model_price_value(model_record, :input_per_million)).to eq("$3.00")
      expect(helper.model_price_value(model_record, :output_per_million)).to eq("$15.00")
    end

    it "returns a dash when pricing is unavailable" do
      model_record = build(:model, pricing: {})

      expect(helper.model_price_value(model_record, :input_per_million)).to eq("—")
    end

    it "returns a dash when pricing is not a hash" do
      model_record = build(:model, pricing: nil)

      expect(helper.model_price_value(model_record, :input_per_million)).to eq("—")
    end
  end

  describe "#models_badge_class" do
    it "returns a stable class for the same badge value" do
      first_class = helper.models_badge_class(:output, "embeddings")

      expect(helper.models_badge_class(:output, "embeddings")).to eq(first_class)
      expect(helper.models_badge_class(:output, "EMBEDDINGS")).to eq(first_class)
    end

    it "returns the same class for the same label across columns" do
      input_class = helper.models_badge_class(:input, "text")

      expect(helper.models_badge_class(:output, "text")).to eq(input_class)
      expect(helper.models_badge_class(:capability, "text")).to eq(input_class)
    end

    it "maps known collections to palette classes" do
      expect(helper.models_badge_class(:input, "text")).to be_in(
        ["badge-secondary", "badge-brand", "badge-success", "badge-warning"],
      )
      expect(helper.models_badge_class(:output, "embeddings")).to be_in(
        ["badge-brand", "badge-success", "badge-warning", "badge-neutral"],
      )
      expect(helper.models_badge_class(:capability, "function_calling")).to be_in(
        ["badge-warning", "badge-secondary", "badge-brand", "badge-success"],
      )
    end

    it "falls back to a neutral badge for unknown collections" do
      expect(helper.models_badge_class(:unknown, "anything")).to eq("badge-neutral")
    end
  end
end
