# frozen_string_literal: true

# == Schema Information
#
# Table name: connectors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  configuration  :jsonb            not null
#  connector_type :string           not null
#  description    :text
#  enabled        :boolean          default(FALSE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_connectors_on_connector_type           (connector_type)
#  index_connectors_on_enabled                  (enabled)
#  index_connectors_on_name                     (name) UNIQUE
#  index_connectors_on_slug                     (slug) UNIQUE
#  index_connectors_on_telegram_webhook_secret  (((configuration ->> 'webhook_secret'::text))) UNIQUE WHERE (((connector_type)::text = 'telegram'::text) AND ((configuration ->> 'webhook_secret'::text) IS NOT NULL))
#
require "rails_helper"

RSpec.describe Connectors::Authentication do
  subject(:authentication) { build(:connectors_authentication) }

  # ── Validations ──────────────────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_inclusion_of(:provider).in_array(described_class::PROVIDERS) }

    it "requires all Keycloak fields" do
      authentication.provider = "keycloak"
      authentication.site_url = nil
      authentication.realm = nil
      authentication.client_id = nil
      authentication.client_secret = nil

      expect(authentication).not_to be_valid
      expect(authentication.errors[:site_url]).to include("can't be blank")
      expect(authentication.errors[:realm]).to include("can't be blank")
      expect(authentication.errors[:client_id]).to include("can't be blank")
      expect(authentication.errors[:client_secret]).to include("can't be blank")
    end

    it "requires only client credentials for Google" do
      google = build(:connectors_authentication, :google, client_id: nil, client_secret: nil)

      expect(google).not_to be_valid
      expect(google.errors[:client_id]).to include("can't be blank")
      expect(google.errors[:client_secret]).to include("can't be blank")
      expect(google.errors[:site_url]).to be_empty
      expect(google.errors[:realm]).to be_empty
    end
  end

  # ── Class Methods ────────────────────────────────────────────────────────────
  describe ".for_provider" do
    it "returns the authentication record for the given provider" do
      auth = create(:connectors_authentication, provider: "keycloak")

      expect(described_class.for_provider("keycloak")).to eq(auth)
    end

    it "returns nil when no record exists for the provider" do
      expect(described_class.for_provider("keycloak")).to be_nil
    end
  end

  describe ".enabled_for_provider?" do
    it "returns true when the connector is enabled for the provider" do
      create(:connectors_authentication, provider: "keycloak", enabled: true)

      expect(described_class).to be_enabled_for_provider("keycloak")
    end

    it "returns false when the connector is disabled for the provider" do
      create(:connectors_authentication, provider: "keycloak", enabled: false)

      expect(described_class).not_to be_enabled_for_provider("keycloak")
    end

    it "returns false when no connector exists for the provider" do
      expect(described_class).not_to be_enabled_for_provider("keycloak")
    end
  end

  # ── Encryption ───────────────────────────────────────────────────────────────
  describe "encryption" do
    it "encrypts client_secret" do
      auth = create(:connectors_authentication, client_secret: "my-secret-key")
      raw_value = Connector.connection.select_value(
        "SELECT configuration ->> 'client_secret' FROM connectors WHERE id = #{auth.id}",
      )

      expect(raw_value).not_to eq("my-secret-key")
      expect(auth.reload.client_secret).to eq("my-secret-key")
    end
  end

  # ── Credential Normalization ─────────────────────────────────────────────────
  describe "blank credential normalization" do
    it "normalizes blank client_secret to nil" do
      auth = create(:connectors_authentication, client_secret: "initial")
      auth.update!(client_secret: "new-secret")

      expect(auth.reload.client_secret).to eq("new-secret")
    end

    it "normalizes empty-string client_secret to nil when saving without validation" do
      auth = build(:connectors_authentication, client_secret: "")
      auth.save(validate: false)
      expect(auth.client_secret).to be_nil
    end
  end

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(
        authentication: {
          provider: "keycloak",
          site_url: "https://auth.example.com",
          realm: "myrealm",
          client_id: "app",
          client_secret: "secret",
        },
      )
      auth = described_class.build_from_params(raw)
      expect(auth).to be_a(described_class)
      expect(auth.provider).to eq("keycloak")
    end
  end

  describe ".required_fields_for" do
    it "returns the required fields for Google" do
      expect(described_class.required_fields_for("google")).to eq([:client_id, :client_secret])
    end
  end

  describe "#summary" do
    it "returns a string combining provider name and Authentication" do
      auth = described_class.new(provider: "keycloak")
      expect(auth.summary).to eq("Keycloak Authentication")
    end

    it "handles nil provider gracefully" do
      auth = described_class.new(provider: nil)
      expect(auth.summary).to eq(" Authentication")
    end
  end
end
