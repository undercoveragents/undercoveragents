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

RSpec.describe Connectors::LlmProvider do
  subject(:llm_provider) { build(:connectors_llm_provider) }

  describe "list_resources metadata" do
    it "declares the connector kind and model support" do
      expect(described_class.list_resources_kind).to eq("llm_connectors")
      expect(described_class.list_resources_title).to eq("LLM Connectors")
      expect(described_class.supports_model_listing?).to be(true)
      expect(described_class.model_provider_key(build(:connectors_llm_provider, provider: "openai"))).to eq("openai")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_inclusion_of(:provider).in_array(described_class::PROVIDER_KEYS) }

    it "rejects request_timeout outside valid range" do
      llm_provider.request_timeout = 0
      expect(llm_provider).not_to be_valid
      expect(llm_provider.errors[:request_timeout]).to be_present
    end

    it "rejects max_retries outside valid range" do
      llm_provider.max_retries = -1
      expect(llm_provider).not_to be_valid
      expect(llm_provider.errors[:max_retries]).to be_present
    end

    it "rejects retry_interval below zero" do
      llm_provider.retry_interval = -1
      expect(llm_provider).not_to be_valid
      expect(llm_provider.errors[:retry_interval]).to be_present
    end

    it "rejects retry_backoff_factor outside valid range" do
      llm_provider.retry_backoff_factor = 0
      expect(llm_provider).not_to be_valid
      expect(llm_provider.errors[:retry_backoff_factor]).to be_present
    end

    it "rejects retry_interval_randomness outside valid range" do
      llm_provider.retry_interval_randomness = -1
      expect(llm_provider).not_to be_valid
      expect(llm_provider.errors[:retry_interval_randomness]).to be_present
    end

    describe "provider-specific required fields" do
      context "with openai provider" do
        subject(:provider) { build(:connectors_llm_provider, :openai, api_key: nil) }

        it "requires api_key" do
          expect(provider).not_to be_valid
          expect(provider.errors[:api_key]).to include("is required for OpenAI")
        end
      end

      context "with anthropic provider" do
        subject(:provider) { build(:connectors_llm_provider, :anthropic, api_key: nil) }

        it "requires api_key" do
          expect(provider).not_to be_valid
          expect(provider.errors[:api_key]).to include("is required for Anthropic")
        end
      end

      context "with bedrock provider" do
        subject(:provider) { build(:connectors_llm_provider, :bedrock, region: nil) }

        it "requires region" do
          expect(provider).not_to be_valid
          expect(provider.errors[:region]).to include("is required for AWS Bedrock")
        end
      end

      context "with azure provider" do
        subject(:provider) { build(:connectors_llm_provider, :azure, api_base: nil) }

        it "requires api_base" do
          expect(provider).not_to be_valid
          expect(provider.errors[:api_base]).to include("is required for Azure OpenAI")
        end
      end

      context "with ollama provider" do
        subject(:provider) { build(:connectors_llm_provider, :ollama, api_base: nil) }

        it "requires api_base" do
          expect(provider).not_to be_valid
          expect(provider.errors[:api_base]).to include("is required for Ollama")
        end
      end

      context "with valid openai api_key" do
        subject(:provider) { build(:connectors_llm_provider, :openai) }

        it "is valid" do
          expect(provider).to be_valid
        end
      end
    end
  end

  describe "constants" do
    it "defines PROVIDER_KEYS" do
      expect(described_class::PROVIDER_KEYS).to be_an(Array)
      expect(described_class::PROVIDER_KEYS).to include("openai", "anthropic", "gemini", "bedrock")
    end

    it "defines PROVIDER_FIELDS for each provider" do
      described_class::PROVIDER_KEYS.each do |provider|
        expect(described_class::PROVIDER_FIELDS).to have_key(provider)
        expect(described_class::PROVIDER_FIELDS[provider]).to have_key(:required)
        expect(described_class::PROVIDER_FIELDS[provider]).to have_key(:optional)
      end
    end
  end

  describe "#provider_label" do
    it "returns human-readable label for known providers" do
      provider = build(:connectors_llm_provider, provider: "openai")
      expect(provider.provider_label).to eq("OpenAI")
    end

    it "returns titleized name for unknown providers" do
      provider = build(:connectors_llm_provider, provider: "openai")
      allow(provider.configurator).to receive(:provider).and_return("custom_provider")
      expect(provider.provider_label).to eq("Custom Provider")
    end
  end

  describe "#provider_fields" do
    it "returns required and optional fields for the provider" do
      provider = build(:connectors_llm_provider, :openai)
      fields = provider.provider_fields
      expect(fields[:required]).to eq([:api_key])
      expect(fields[:optional]).to include(:api_base, :organization_id)
    end
  end

  describe "#all_provider_fields" do
    it "returns all fields for the provider" do
      provider = build(:connectors_llm_provider, :openai)
      expect(provider.all_provider_fields).to include(:api_key, :api_base, :organization_id, :project_id)
    end
  end

  describe "#build_context" do
    it "returns a RubyLLM context for OpenAI" do
      provider = build(:connectors_llm_provider, :openai, api_key: "sk-test-123")
      context = provider.build_context
      expect(context).to be_a(RubyLLM::Context)
      expect(context.config.openai_api_key).to eq("sk-test-123")
    end

    it "configures OpenAI optional fields" do
      provider = build(:connectors_llm_provider, :openai,
                       api_base: "https://custom.openai.com",
                       organization_id: "org-123",
                       project_id: "proj-456",
                       use_system_role: true,)
      context = provider.build_context
      expect(context.config.openai_api_base).to eq("https://custom.openai.com")
      expect(context.config.openai_organization_id).to eq("org-123")
      expect(context.config.openai_project_id).to eq("proj-456")
      expect(context.config.openai_use_system_role).to be(true)
    end

    it "returns a RubyLLM context for Anthropic" do
      provider = build(:connectors_llm_provider, :anthropic, api_key: "sk-ant-test-123")
      context = provider.build_context
      expect(context).to be_a(RubyLLM::Context)
      expect(context.config.anthropic_api_key).to eq("sk-ant-test-123")
    end

    it "configures Gemini" do
      provider = build(:connectors_llm_provider, :gemini)
      context = provider.build_context
      expect(context.config.gemini_api_key).to eq("gemini-key-12345")
    end

    it "configures Gemini with custom api_base" do
      provider = build(:connectors_llm_provider, :gemini, api_base: "https://custom.gemini.com")
      context = provider.build_context
      expect(context.config.gemini_api_base).to eq("https://custom.gemini.com")
    end

    it "configures bedrock with region" do
      provider = build(:connectors_llm_provider, :bedrock)
      context = provider.build_context
      expect(context.config.bedrock_region).to eq("us-east-1")
    end

    it "configures bedrock with optional credentials" do
      provider = build(:connectors_llm_provider, :bedrock,
                       api_key: "AKIA1234",
                       secret_key: "secret-key",
                       session_token: "session-token",)
      context = provider.build_context
      expect(context.config.bedrock_api_key).to eq("AKIA1234")
      expect(context.config.bedrock_secret_key).to eq("secret-key")
      expect(context.config.bedrock_session_token).to eq("session-token")
    end

    it "configures azure with api_base" do
      provider = build(:connectors_llm_provider, :azure)
      context = provider.build_context
      expect(context.config.azure_api_base).to eq("https://my-resource.openai.azure.com")
    end

    it "configures azure with optional fields" do
      provider = build(:connectors_llm_provider, :azure,
                       api_key: "azure-key",
                       auth_token: "auth-token-123",)
      context = provider.build_context
      expect(context.config.azure_api_key).to eq("azure-key")
      expect(context.config.azure_ai_auth_token).to eq("auth-token-123")
    end

    it "configures DeepSeek" do
      provider = build(:connectors_llm_provider, provider: "deepseek", api_key: "ds-key")
      context = provider.build_context
      expect(context.config.deepseek_api_key).to eq("ds-key")
    end

    it "configures Mistral" do
      provider = build(:connectors_llm_provider, provider: "mistral", api_key: "mistral-key")
      context = provider.build_context
      expect(context.config.mistral_api_key).to eq("mistral-key")
    end

    it "configures OpenRouter" do
      provider = build(:connectors_llm_provider, provider: "openrouter", api_key: "or-key")
      context = provider.build_context
      expect(context.config.openrouter_api_key).to eq("or-key")
    end

    it "configures Perplexity" do
      provider = build(:connectors_llm_provider, provider: "perplexity", api_key: "pplx-key")
      context = provider.build_context
      expect(context.config.perplexity_api_key).to eq("pplx-key")
    end

    it "configures xAI" do
      provider = build(:connectors_llm_provider, provider: "xai", api_key: "xai-key")
      context = provider.build_context
      expect(context.config.xai_api_key).to eq("xai-key")
    end

    it "configures ollama with api_base" do
      provider = build(:connectors_llm_provider, :ollama)
      context = provider.build_context
      expect(context.config.ollama_api_base).to eq("http://localhost:11434/v1")
    end

    it "configures GPUStack" do
      provider = build(:connectors_llm_provider, provider: "gpustack", api_base: "http://gpu:8080")
      context = provider.build_context
      expect(context.config.gpustack_api_base).to eq("http://gpu:8080")
    end

    it "configures GPUStack with optional api_key" do
      provider = build(:connectors_llm_provider, provider: "gpustack", api_base: "http://gpu:8080", api_key: "gpu-key")
      context = provider.build_context
      expect(context.config.gpustack_api_key).to eq("gpu-key")
    end

    it "configures Vertex AI" do
      provider = build(:connectors_llm_provider, provider: "vertexai", project_id: "my-project", region: "us-central1")
      context = provider.build_context
      expect(context.config.vertexai_project_id).to eq("my-project")
      expect(context.config.vertexai_location).to eq("us-central1")
    end

    it "applies connection settings" do
      provider = build(:connectors_llm_provider, :openai, request_timeout: 300, max_retries: 5)
      context = provider.build_context
      expect(context.config.request_timeout).to eq(300)
      expect(context.config.max_retries).to eq(5)
    end

    it "applies http proxy when present" do
      provider = build(:connectors_llm_provider, :openai, :with_proxy)
      context = provider.build_context
      expect(context.config.http_proxy).to eq("http://proxy.example.com:8080")
    end

    it "does not set http proxy when absent" do
      provider = build(:connectors_llm_provider, :openai, http_proxy: nil)
      context = provider.build_context
      expect(context.config.http_proxy).to be_nil
    end

    context "when encrypted credentials cannot be decrypted" do
      it "raises CredentialDecryptionError with a descriptive message" do
        connector = create(:connector, :llm_provider, :enabled)

        allow(connector.configurator).to receive(:api_key)
          .and_raise(ActiveRecord::Encryption::Errors::Decryption)

        expect { connector.build_context }.to raise_error(
          Connectors::LlmProvider::CredentialDecryptionError,
          /Cannot decrypt credentials for connector '#{Regexp.escape(connector.name)}'/,
        )
      end

      it "includes re-entry instructions in the error message" do
        connector = create(:connector, :llm_provider, :enabled)

        allow(connector.configurator).to receive(:api_key)
          .and_raise(ActiveRecord::Encryption::Errors::Decryption)

        expect { connector.build_context }.to raise_error(
          Connectors::LlmProvider::CredentialDecryptionError,
          /re-enter the API keys/,
        )
      end

      it "uses the provider name for unsaved providers" do
        provider = build(:connectors_llm_provider, :openai)

        allow(provider.configurator).to receive(:api_key)
          .and_raise(ActiveRecord::Encryption::Errors::Decryption)

        expect { provider.build_context }.to raise_error(
          Connectors::LlmProvider::CredentialDecryptionError,
          /Cannot decrypt credentials for connector '#{Regexp.escape(provider.name)}'/,
        )
      end

      it "falls back to the provider label when no connector record is attached" do
        configurator = described_class.new(provider: "openai")
        allow(configurator).to receive(:apply_provider_config)
          .and_raise(ActiveRecord::Encryption::Errors::Decryption)

        expect { configurator.build_context }.to raise_error(
          Connectors::LlmProvider::CredentialDecryptionError,
          /Cannot decrypt credentials for connector 'OpenAI'/,
        )
      end
    end
  end

  describe "#display_provider" do
    it "returns the provider label" do
      provider = build(:connectors_llm_provider, :anthropic)
      expect(provider.display_provider).to eq("Anthropic")
    end
  end

  describe "blank credential normalization (private)" do
    it "normalizes blank api_key to nil" do
      provider = build(:connectors_llm_provider, :ollama, api_key: "")
      provider.configurator.send(:normalize_blank_credentials)
      expect(provider.api_key).to be_nil
    end

    it "preserves present auth_token" do
      provider = build(:connectors_llm_provider, :azure, auth_token: "my-auth-token")
      provider.configurator.send(:normalize_blank_credentials)
      expect(provider.auth_token).to eq("my-auth-token")
    end

    it "normalizes blank auth_token to nil" do
      provider = build(:connectors_llm_provider, :openai, auth_token: "")
      provider.configurator.send(:normalize_blank_credentials)
      expect(provider.auth_token).to be_nil
    end

    it "preserves present secret_key" do
      provider = build(:connectors_llm_provider, :bedrock)
      provider.configurator.send(:normalize_blank_credentials)
      expect(provider.secret_key).to be_present
    end

    it "preserves present session_token" do
      provider = build(:connectors_llm_provider, :bedrock, session_token: "sess-token")
      provider.configurator.send(:normalize_blank_credentials)
      expect(provider.session_token).to eq("sess-token")
    end
  end

  describe "sensitive configuration persistence" do
    it "does not re-encrypt api_key when only non-sensitive fields change" do
      provider = create(:connectors_llm_provider, :openai)
      initial_ciphertext = provider.configuration["api_key"]

      provider.update!(description: "Updated description")

      expect(provider.reload.configuration["api_key"]).to eq(initial_ciphertext)
    end
  end

  describe "with an unknown/unsupported provider" do
    let(:provider) do
      p = build(:connectors_llm_provider)
      allow(p.configurator).to receive(:provider).and_return("unknown_custom_provider")
      p
    end

    it "skips required field validation when provider has no PROVIDER_FIELDS entry" do
      # required_provider_fields_present: return unless fields → covers TRUE branch
      errors_before = provider.errors.full_messages
      provider.configurator.send(:required_provider_fields_present)
      expect(provider.errors.full_messages).to eq(errors_before)
    end

    it "skips provider config when provider has no PROVIDER_CONFIG_MAPPING entry" do
      # apply_provider_config: return unless mapping → covers TRUE branch
      context = provider.build_context
      expect(context).to be_a(RubyLLM::Context)
    end
  end

  describe "required_provider_fields_present with a boolean required field" do
    it "skips validation error for boolean fields (BOOLEAN_FIELDS.include? true branch)" do
      # Stub PROVIDER_FIELDS so that a boolean field (use_system_role) appears in required
      # This covers the `next if BOOLEAN_FIELDS.include?(field)` true branch.
      provider = build(:connectors_llm_provider, provider: "openai")
      stubbed_fields = {
        "openai" => { required: [:use_system_role, :api_key], optional: [] },
      }
      stub_const("Connectors::LlmProvider::PROVIDER_FIELDS", stubbed_fields)
      # With api_key present and use_system_role a boolean, no validation errors should be added
      # for use_system_role (it gets skipped via the boolean check)
      provider.configurator.send(:required_provider_fields_present)
      expect(provider.errors[:use_system_role]).to be_empty
    end
  end

  describe ".build_from_params" do
    it "builds an instance from raw ActionController::Parameters" do
      raw = ActionController::Parameters.new(
        llm_provider: { provider: "openai", api_key: "sk-test" },
      )
      lp = described_class.build_from_params(raw)
      expect(lp).to be_a(described_class)
      expect(lp.provider).to eq("openai")
    end
  end

  describe "#use_system_role?" do
    it "returns false when use_system_role is nil" do
      provider = build(:connectors_llm_provider, provider: "openai")
      expect(provider.configurator.use_system_role?).to be(false)
    end

    it "returns true when use_system_role is true" do
      provider = build(:connectors_llm_provider, provider: "openai",
                                                 configuration: { use_system_role: true },)
      expect(provider.configurator.use_system_role?).to be(true)
    end
  end

  describe "#summary" do
    it "returns the provider label" do
      provider = build(:connectors_llm_provider, provider: "openai")
      expect(provider.configurator.summary).to be_a(String)
      expect(provider.configurator.summary).not_to be_empty
    end
  end

  describe "#to_configuration" do
    it "removes blank sensitive fields from output" do
      provider = build(:connectors_llm_provider, :openai, secret_key: "", session_token: nil)
      config = provider.configurator.to_configuration
      expect(config).not_to have_key("secret_key")
      expect(config).not_to have_key("session_token")
    end

    it "preserves present sensitive fields" do
      provider = build(:connectors_llm_provider, :openai, api_key: "sk-real")
      config = provider.configurator.to_configuration
      expect(config["api_key"]).to eq("sk-real")
    end
  end

  describe "#apply_config_entry (private)" do
    it "skips Hash spec entry with :if => :present? when value is blank" do
      provider = build(:connectors_llm_provider, :openai, api_base: "")
      context = provider.build_context
      expect(context.config.openai_api_base).to be_nil
    end

    it "applies Hash spec entry without :if condition unconditionally" do
      provider = build(:connectors_llm_provider, :openai, use_system_role: false)
      context = provider.build_context
      expect(context.config.openai_use_system_role).to be(false)
    end
  end

  describe "#required_provider_fields_present with blank provider" do
    it "skips validation when provider is blank" do
      provider = build(:connectors_llm_provider, provider: "openai")
      allow(provider.configurator).to receive(:provider).and_return("")
      provider.configurator.send(:required_provider_fields_present)
      expect(provider.errors).to be_empty
    end
  end

  describe "#apply_connection_settings" do
    it "skips http_proxy when not present" do
      provider = build(:connectors_llm_provider, :openai, http_proxy: nil)
      context = provider.build_context
      expect(context.config.http_proxy).to be_nil
    end
  end
end
