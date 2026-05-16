# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuthHelper do
  describe "#auth_provider_label" do
    it "returns Keycloak for keycloak provider" do
      expect(helper.auth_provider_label("keycloak")).to eq("Keycloak")
    end

    it "returns Keycloak for keycloak_openid provider" do
      expect(helper.auth_provider_label("keycloak_openid")).to eq("Keycloak")
    end

    it "returns titleized name for other providers" do
      expect(helper.auth_provider_label("google")).to eq("Google")
    end

    it "returns Unknown for nil provider" do
      expect(helper.auth_provider_label(nil)).to eq("Unknown")
    end
  end

  describe "#auth_provider_icon" do
    it "returns key icon for keycloak provider" do
      expect(helper.auth_provider_icon("keycloak")).to eq("fa-solid fa-key")
    end

    it "returns key icon for keycloak_openid provider" do
      expect(helper.auth_provider_icon("keycloak_openid")).to eq("fa-solid fa-key")
    end

    it "returns sign-in icon for other providers" do
      expect(helper.auth_provider_icon("google")).to eq("fa-solid fa-right-to-bracket")
    end
  end
end
