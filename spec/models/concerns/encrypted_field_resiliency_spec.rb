# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe EncryptedConfigurationJsonType do
  def corrupt_column(record, column)
    record.class.where(id: record.id)
          .update_all("configuration = jsonb_set(configuration, '{#{column}}', '\"corrupted-not-encrypted\"'::jsonb)") # rubocop:disable Rails/SkipsModelValidations
  end

  describe "decryption resiliency" do
    let!(:connector) { create(:connector, :llm_provider, :enabled) }
    let(:provider_id) { connector.id }

    before { corrupt_column(connector, :api_key) }

    it "loads the record without raising" do
      expect { Connectors::LlmProvider.find(provider_id) }.not_to raise_error
    end

    it "sets the corrupted field to nil in memory" do
      provider = Connectors::LlmProvider.find(provider_id)
      expect(provider.api_key).to be_nil
    end

    it "leaves non-encrypted fields intact" do
      provider = Connectors::LlmProvider.find(provider_id)
      expect(provider.provider).to eq("openai")
    end

    it "does not write nil back to the database" do
      Connectors::LlmProvider.find(provider_id)
      raw = Connectors::LlmProvider.connection.select_value(
        "SELECT configuration ->> 'api_key' FROM connectors WHERE id = #{provider_id}",
      )
      expect(raw).to eq("corrupted-not-encrypted")
    end

    it "allows update! with a new value without raising" do
      provider = Connectors::LlmProvider.find(provider_id)
      expect { provider.update!(api_key: "new-valid-key") }.not_to raise_error
      expect(Connectors::LlmProvider.find(provider_id).api_key).to eq("new-valid-key")
    end
  end

  describe "after_find — when all encrypted fields decrypt successfully" do
    let(:provider) { create(:connector, :llm_provider, :enabled) }

    it "returns the stored api_key value" do
      loaded = Connectors::LlmProvider.find(provider.id)
      expect(loaded.api_key).to be_present
    end
  end

  describe "after_find — SqlDatabase encrypted_password" do
    let!(:connector) { create(:connector, :sql_database, :enabled) }
    let(:db_id) { connector.id }

    before { corrupt_column(connector, :encrypted_password) }

    it "loads the record without raising" do
      expect { Connectors::SqlDatabase.find(db_id) }.not_to raise_error
    end

    it "clears the corrupted encrypted_password to nil" do
      db = Connectors::SqlDatabase.find(db_id)
      expect(db.encrypted_password).to be_nil
    end
  end

  describe "encryption round-trip" do
    it "encrypts and decrypts sensitive fields transparently" do
      provider = create(:connectors_llm_provider)
      loaded = Connectors::LlmProvider.find(provider.id)
      expect(loaded.api_key).to be_present
    end

    it "returns raw value when decrypt raises unexpected StandardError" do
      provider = create(:connectors_llm_provider)
      raw_ciphertext = Connectors::LlmProvider.connection.select_value(
        "SELECT configuration ->> 'api_key' FROM connectors WHERE id = #{provider.id}",
      )

      allow(ActiveRecord::Encryption.encryptor).to receive(:decrypt).and_raise(StandardError, "boom")

      loaded = Connectors::LlmProvider.find(provider.id)
      expect(loaded.api_key).to eq(raw_ciphertext)
    end

    it "returns empty hash for nil deserialization" do
      type = described_class.new
      expect(type.deserialize(nil)).to eq({})
    end

    it "returns empty hash for non-hash serialization input" do
      type = described_class.new
      serialized = type.serialize(123)
      expect(type.deserialize(serialized)).to eq({})
    end
  end

  describe "model-level defaults and casting" do
    it "applies SQL connector defaults on initialization" do
      db = Connectors::SqlDatabase.new
      expect(db.adapter_type).to eq("postgresql")
      expect(db.pool_size).to eq(5)
      expect(db.timeout).to eq(5000)
      expect(db.max_results).to eq(100)
    end

    it "defaults SQL connector boolean fields" do
      db = Connectors::SqlDatabase.new
      expect(db.read_only).to be(true)
      expect(db.ssl_enabled).to be(false)
    end

    it "casts typed SQL connector values via before_validation" do
      db = create(:connectors_sql_database, pool_size: "12", timeout: "6500", read_only: "0")
      loaded = Connectors::SqlDatabase.find(db.id)

      expect(loaded.pool_size).to eq(12)
      expect(loaded.timeout).to eq(6500)
      expect(loaded.read_only?).to be(false)
    end

    it "applies MCP connector defaults on initialization" do
      mcp = Connectors::McpServer.new
      expect(mcp.transport_type).to eq("stdio")
      expect(mcp.request_timeout).to eq(8000)
      expect(mcp.oauth_enabled?).to be(false)
      expect(mcp.env_vars).to eq({})
      expect(mcp.headers).to eq({})
    end

    it "applies LLM provider defaults on initialization" do
      llm = Connectors::LlmProvider.new
      expect(llm.request_timeout).to eq(120)
      expect(llm.max_retries).to eq(3)
      expect(llm.retry_interval).to eq(0.1)
      expect(llm.retry_backoff_factor).to eq(2)
      expect(llm.retry_interval_randomness).to eq(0.5)
    end

    it "defaults LLM provider use_system_role to false" do
      llm = Connectors::LlmProvider.new
      expect(llm.use_system_role).to be(false)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
