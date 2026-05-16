# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::ProfileLinksController do
  let(:controller_class) do
    Class.new(described_class) do
      attr_writer :test_flash

      def flash = @test_flash || super
    end
  end
  let(:profile_links_controller) { controller_class.new }

  it "returns an empty hash for malformed pending token flash entries" do
    flash = ActionDispatch::Flash::FlashHash.new
    flash[:telegram_link_tokens] = "invalid"
    profile_links_controller.test_flash = flash

    expect(profile_links_controller.send(:pending_tokens)).to eq({})
  end

  it "returns the stored flash token hash when it is well formed" do
    flash = ActionDispatch::Flash::FlashHash.new
    flash[:telegram_link_tokens] = { "1" => "token" }
    profile_links_controller.test_flash = flash

    expect(profile_links_controller.send(:pending_tokens)).to eq({ "1" => "token" })
  end
end
