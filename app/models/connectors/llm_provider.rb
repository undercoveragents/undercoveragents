# frozen_string_literal: true

module Connectors
  # Configurator for LLM Provider connectors.
  # Stores provider credentials and settings in the Connector's JSONB configuration column.
  class LlmProvider
    include UndercoverAgents::PluginSystem::Configurator
    include ConnectorPlugin

    SENSITIVE_FIELDS = [:api_key, :secret_key, :session_token, :auth_token].freeze

    PROVIDER_KEYS = [
      "openai", "anthropic", "gemini", "bedrock", "azure", "deepseek", "mistral",
      "openrouter", "perplexity", "xai", "ollama", "gpustack", "vertexai",
    ].freeze

    PROVIDER_FIELDS = {
      "openai" => { required: [:api_key], optional: [:api_base, :organization_id, :project_id, :use_system_role] },
      "anthropic" => { required: [:api_key], optional: [] },
      "gemini" => { required: [:api_key], optional: [:api_base] },
      "bedrock" => { required: [:region], optional: [:api_key, :secret_key, :session_token] },
      "azure" => { required: [:api_base], optional: [:api_key, :auth_token] },
      "deepseek" => { required: [:api_key], optional: [] },
      "mistral" => { required: [:api_key], optional: [] },
      "openrouter" => { required: [:api_key], optional: [] },
      "perplexity" => { required: [:api_key], optional: [] },
      "xai" => { required: [:api_key], optional: [] },
      "ollama" => { required: [:api_base], optional: [] },
      "gpustack" => { required: [:api_base], optional: [:api_key] },
      "vertexai" => { required: [:project_id, :region], optional: [] },
    }.freeze

    PROVIDER_CONFIG_MAPPING = {
      "openai" => {
        api_key: :openai_api_key, api_base: { key: :openai_api_base, if: :present? },
        organization_id: { key: :openai_organization_id, if: :present? },
        project_id: { key: :openai_project_id, if: :present? }, use_system_role: { key: :openai_use_system_role },
      },
      "anthropic" => { api_key: :anthropic_api_key },
      "gemini" => { api_key: :gemini_api_key, api_base: { key: :gemini_api_base, if: :present? } },
      "bedrock" => {
        api_key: { key: :bedrock_api_key, if: :present? }, secret_key: { key: :bedrock_secret_key, if: :present? },
        region: :bedrock_region, session_token: { key: :bedrock_session_token, if: :present? },
      },
      "azure" => {
        api_base: :azure_api_base, api_key: { key: :azure_api_key, if: :present? },
        auth_token: { key: :azure_ai_auth_token, if: :present? },
      },
      "deepseek" => { api_key: :deepseek_api_key },
      "mistral" => { api_key: :mistral_api_key },
      "openrouter" => { api_key: :openrouter_api_key },
      "perplexity" => { api_key: :perplexity_api_key },
      "xai" => { api_key: :xai_api_key },
      "ollama" => { api_base: :ollama_api_base },
      "gpustack" => { api_base: :gpustack_api_base, api_key: { key: :gpustack_api_key, if: :present? } },
      "vertexai" => { project_id: :vertexai_project_id, region: :vertexai_location },
    }.freeze

    BOOLEAN_FIELDS = [:use_system_role].freeze
    FORM_PARTIAL_PATH = Rails.root.join("app/views/admin/connectors/llm_provider").to_s.freeze

    attribute :provider, :string
    attribute :api_key, :string
    attribute :api_base, :string
    attribute :organization_id, :string
    attribute :project_id, :string
    attribute :secret_key, :string
    attribute :region, :string
    attribute :session_token, :string
    attribute :auth_token, :string
    attribute :use_system_role, :boolean, default: false
    attribute :http_proxy, :string
    attribute :request_timeout, :integer, default: 120
    attribute :max_retries, :integer, default: 3
    attribute :retry_interval, :float, default: 0.1
    attribute :retry_backoff_factor, :integer, default: 2
    attribute :retry_interval_randomness, :float, default: 0.5

    validates :provider, presence: true, inclusion: { in: PROVIDER_KEYS }
    validates :request_timeout, numericality: { greater_than: 0, less_than_or_equal_to: 600 }
    validates :max_retries, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
    validates :retry_interval, numericality: { greater_than_or_equal_to: 0 }
    validates :retry_backoff_factor, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
    validates :retry_interval_randomness, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
    validate :required_provider_fields_present

    key "llm_provider"
    label "LLM Provider"
    icon "fa-solid fa-brain"
    description "Connect to an LLM provider (OpenAI, Anthropic, Gemini, etc.) " \
                "to power your agents with language models."
    sensitive_keys SENSITIVE_FIELDS

    def self.permitted_params(params)
      params.expect(llm_provider: [
                      :provider, :api_key, :api_base, :organization_id, :project_id,
                      :secret_key, :region, :session_token, :auth_token, :use_system_role,
                      :http_proxy, :request_timeout, :max_retries, :retry_interval,
                      :retry_backoff_factor, :retry_interval_randomness,
                    ])
    end

    def self.build_from_params(params)
      new(permitted_params(params))
    end

    def self.param_key = "llm_provider"
    def self.list_resources_kind = "llm_connectors"
    def self.list_resources_title = "LLM Connectors"
    def self.supports_model_listing? = true
    def self.model_provider_key(connector) = connector.provider

    def self.providers_for_select
      PROVIDER_KEYS.map { |key| [I18n.t("connectors.llm_provider.providers.#{key}"), key] }
    end

    def self.field_label(field)
      I18n.t("connectors.llm_provider.fields.labels.#{field}", default: field.to_s.titleize)
    end

    def self.field_hint(field)
      I18n.t("connectors.llm_provider.fields.hints.#{field}", default: nil)
    end

    def use_system_role?
      !!use_system_role
    end

    def provider_label
      I18n.t("connectors.llm_provider.providers.#{provider}", default: provider.to_s.titleize)
    end

    def provider_fields
      PROVIDER_FIELDS[provider] || { required: [], optional: [] }
    end

    def all_provider_fields
      fields = provider_fields
      fields[:required] + fields[:optional]
    end

    def display_provider
      provider_label
    end

    def summary
      provider_label
    end

    def build_context
      RubyLLM.context do |config|
        apply_provider_config(config)
        apply_connection_settings(config)
      end
    rescue ActiveRecord::Encryption::Errors::Decryption
      connector_name = _connector_record&.name || provider_label
      raise CredentialDecryptionError, connector_name
    end

    class CredentialDecryptionError < StandardError
      def initialize(connector_name)
        super(
          "Cannot decrypt credentials for connector '#{connector_name}'. " \
          "Please re-enter the API keys in the connector settings.",
        )
      end
    end

    def form_partial_path
      FORM_PARTIAL_PATH
    end

    def show_partial_path
      FORM_PARTIAL_PATH
    end

    def to_configuration
      attrs = super
      SENSITIVE_FIELDS.each { |field| attrs.delete(field.to_s) if attrs[field.to_s].blank? }
      attrs
    end

    private

    def apply_provider_config(config)
      mapping = PROVIDER_CONFIG_MAPPING[provider]
      return unless mapping

      mapping.each { |attr, spec| apply_config_entry(config, attr, spec) }
    end

    def apply_config_entry(config, attr, spec)
      if spec.is_a?(Symbol)
        config.send(:"#{spec}=", send(attr))
      else
        value = send(attr)
        config.send(:"#{spec[:key]}=", value) unless spec[:if] == :present? && value.blank?
      end
    end

    def apply_connection_settings(config)
      config.http_proxy = http_proxy if http_proxy.present?
      config.request_timeout = request_timeout
      config.max_retries = max_retries
      config.retry_interval = retry_interval
      config.retry_backoff_factor = retry_backoff_factor
      config.retry_interval_randomness = retry_interval_randomness
    end

    def required_provider_fields_present
      return if provider.blank?

      fields = PROVIDER_FIELDS[provider]
      return unless fields

      fields[:required].each do |field|
        next if BOOLEAN_FIELDS.include?(field)
        next if send(field).present?

        errors.add(field,
                   I18n.t("connectors.llm_provider.validation.required_for",
                          provider: provider_label,),)
      end
    end
  end
end
