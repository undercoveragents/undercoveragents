# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectorsHelper do
  describe "#connector_type_label" do
    it "returns 'Telegram' for telegram connectors" do
      connector = build(:connector, :telegram)
      expect(helper.connector_type_label(connector)).to eq("Telegram")
    end
  end

  describe "#connector_type_icon" do
    it "returns telegram icon for telegram connectors" do
      connector = build(:connector, :telegram)
      expect(helper.connector_type_icon(connector)).to eq("fa-brands fa-telegram")
    end
  end
end
