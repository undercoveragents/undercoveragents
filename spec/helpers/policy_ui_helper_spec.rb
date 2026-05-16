# frozen_string_literal: true

require "rails_helper"

RSpec.describe PolicyUiHelper do
  describe "#disabled_action_classes" do
    it "returns the original classes when the action is not disabled" do
      expect(helper.disabled_action_classes("btn btn-primary", disabled: false)).to eq("btn btn-primary")
    end
  end
end
