# frozen_string_literal: true

module Connectors
  # Configurator for Authentication connectors (Keycloak, etc.).
  # Stores provider credentials in the Connector's JSONB configuration column.
  class Authentication
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    SENSITIVE_FIELDS = [:client_secret].freeze
    PROVIDERS = ["keycloak", "google"].freeze
    REQUIRED_FIELDS_BY_PROVIDER = {
      "keycloak" => [:site_url, :realm, :client_id, :client_secret],
      "google" => [:client_id, :client_secret],
    }.freeze

    # ── Attributes ────────────────────────────────────────────────

    attribute :provider, :string
    attribute :site_url, :string
    attribute :realm, :string
    attribute :client_id, :string
    attribute :client_secret, :string

    # ── Validations ───────────────────────────────────────────────

    validates :provider, presence: true, inclusion: { in: PROVIDERS }
    validate :required_fields_for_provider

    # ── Plugin Protocol ───────────────────────────────────────────

    key "authentication"
    label "Authentication"
    icon "fa-solid fa-shield-halved"
    description "Connect to an external authentication provider (Keycloak, etc.) " \
                "to enable SSO sign-in for your users."
    sensitive_keys SENSITIVE_FIELDS

    def self.permitted_params(params)
      params.expect(authentication: [:provider, :site_url, :realm, :client_id, :client_secret])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def self.param_key = "authentication"

    # ── Class Helpers (querying via Connector) ────────────────────

    def self.for_provider(provider_name)
      Connector.by_type("authentication")
               .where("configuration ->> 'provider' = ?", provider_name)
               .first
    end

    def self.enabled_for_provider?(provider_name)
      Connector.by_type("authentication")
               .enabled
               .exists?(["configuration ->> 'provider' = ?", provider_name])
    end

    # ── Instance Methods ──────────────────────────────────────────

    def summary
      "#{provider&.titleize} Authentication"
    end

    def self.required_fields_for(provider)
      REQUIRED_FIELDS_BY_PROVIDER.fetch(provider.to_s, [])
    end

    # ── Serialization ─────────────────────────────────────────────

    def to_configuration
      attrs = super
      attrs.delete("client_secret") if attrs["client_secret"].blank?
      attrs
    end

    private

    def required_fields_for_provider
      self.class.required_fields_for(provider).each do |field|
        errors.add(field, :blank) if public_send(field).blank?
      end
    end
  end
end
