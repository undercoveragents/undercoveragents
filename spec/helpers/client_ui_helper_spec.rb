# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientUiHelper do
  describe "#current_client_label" do
    it "uses the current client name when a label falls back to defaults" do
      helper.define_singleton_method(:current_client) do
        {
          name: "Acme Support",
          labels: {},
        }
      end

      expect(helper.current_client_label(:welcome_heading)).to eq("Welcome to Acme Support")
      expect(helper.current_client_label(:new_chat_label)).to eq("New chat")
    end
  end
end
