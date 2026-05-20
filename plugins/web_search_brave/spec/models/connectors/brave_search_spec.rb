# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::BraveSearch do
  subject(:brave_search) { build(:connectors_brave_search) }

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(brave_search: { api_key: "brave-param-key" })

      connector = described_class.build_from_params(raw)

      expect(connector).to be_a(described_class)
      expect(connector.api_key).to eq("brave-param-key")
    end
  end

  describe "validations" do
    it "requires an api_key on new records" do
      brave_search.api_key = nil

      expect(brave_search).not_to be_valid
      expect(brave_search.errors[:api_key]).to include("can't be blank")
    end

    it "allows persisted connectors to keep the existing api_key when the form submits blank" do
      connector = create(:connectors_brave_search, api_key: "brave-existing-key")

      connector.api_key = ""
      connector.name = "Updated Brave Search"

      expect(connector).to be_valid
      connector.save!
      expect(connector.reload.api_key).to eq("brave-existing-key")
    end
  end

  describe ".current_connector" do
    around do |example|
      previous_tenant = Current.tenant
      Current.tenant = tenant
      example.run
    ensure
      Current.tenant = previous_tenant
    end

    let(:tenant) { create(:tenant) }

    it "returns the first enabled Brave Search connector for the current tenant" do
      create(:connectors_brave_search, tenant:, enabled: false, name: "Disabled")
      create(:connectors_brave_search, tenant:, enabled: true, name: "Bravo")
      create(:connectors_brave_search, tenant:, enabled: true, name: "Zulu")
      create(:connectors_brave_search, tenant: create(:tenant), enabled: true, name: "Other Tenant")

      expect(described_class.current_connector.name).to eq("Bravo")
    end

    it "returns nil without tenant context" do
      Current.tenant = nil

      expect(described_class.current_connector).to be_nil
    end
  end

  describe "encryption" do
    it "encrypts the api_key" do
      connector = create(:connectors_brave_search, api_key: "brave-secret-key")
      raw_value = Connector.connection.select_value(
        "SELECT configuration ->> 'api_key' FROM connectors WHERE id = #{connector.id}",
      )

      expect(raw_value).not_to eq("brave-secret-key")
      expect(connector.reload.api_key).to eq("brave-secret-key")
    end
  end

  describe "#summary" do
    it "reports whether the api_key is configured" do
      expect(build(:connectors_brave_search).summary).to eq("Brave Search API key configured")
      expect(build(:connectors_brave_search, api_key: nil).summary).to eq("Brave Search API key missing")
    end

    it "treats missing backing connector records as not configured" do
      connector = described_class.new(api_key: nil)

      expect(connector.api_key_configured?).to be(false)
    end
  end

  describe "persisted credential fallback" do
    it "returns nil when decrypting the stored api_key fails" do
      connector = described_class.new(api_key: nil)
      backing_record = build(:connectors_brave_search)
      connector._connector_record = backing_record
      allow(backing_record).to receive(:configuration).and_raise(ActiveRecord::Encryption::Errors::Decryption)

      expect(connector.send(:persisted_api_key)).to be_nil
    end
  end
end
