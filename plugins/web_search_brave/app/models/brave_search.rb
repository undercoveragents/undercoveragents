# frozen_string_literal: true

module Connectors
  class BraveSearch
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    SENSITIVE_FIELDS = [:api_key].freeze
    FORM_PARTIAL_PATH = File.expand_path("../views", __dir__).freeze

    attribute :api_key, :string

    validate :api_key_present

    key "brave_search"
    label "Brave Search"
    icon "fa-solid fa-compass"
    description "Connect to Brave Search with an encrypted API key for authenticated public web search."
    sensitive_keys SENSITIVE_FIELDS

    def self.permitted_params(params)
      params.expect(brave_search: [:api_key])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def self.param_key = "brave_search"

    def self.current_connector
      return unless Current.tenant

      scoped.enabled.ordered.first
    end

    def summary
      api_key_configured? ? "Brave Search API key configured" : "Brave Search API key missing"
    end

    def api_key_configured?
      api_key.present? || persisted_api_key.present?
    end

    def form_partial_path
      FORM_PARTIAL_PATH
    end

    def show_partial_path
      FORM_PARTIAL_PATH
    end

    def to_configuration
      attrs = super
      attrs["api_key"] = persisted_api_key if attrs["api_key"].blank? && persisted_api_key.present?
      attrs
    end

    private

    def api_key_present
      return if api_key.present? || persisted_api_key.present?

      errors.add(:api_key, :blank)
    end

    def persisted_api_key
      _connector_record&.configuration&.dig("api_key").presence
    rescue ActiveRecord::Encryption::Errors::Decryption
      nil
    end
  end
end
