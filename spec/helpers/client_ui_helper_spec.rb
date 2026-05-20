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

  describe "#current_client_message_actions" do
    it "falls back to defaults when no current client settings are available" do
      helper.define_singleton_method(:resolved_current_client_settings) { nil }

      expect(helper.current_client_message_actions).to include(
        "visibility" => "hover",
        "copy_assistant_response" => true,
        "copy_user_message" => true,
        "retry_assistant_message" => false,
      )
    end
  end
end
