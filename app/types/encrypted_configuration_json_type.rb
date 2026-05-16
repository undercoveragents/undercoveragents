# frozen_string_literal: true

# Transparent encryption/decryption for sensitive fields stored in a JSONB column.
# Only handles encryption — defaults and type casting belong in the model.
#
# sensitive_keys can be:
#   - An array of symbols/strings: static keys to encrypt
#   - A Proc that receives the hash and returns an array of keys to encrypt
class EncryptedConfigurationJsonType < ActiveRecord::Type::Json
  def initialize(sensitive_keys: [])
    super()
    @sensitive_keys_config = sensitive_keys
  end

  def deserialize(value)
    hash = super
    return {} unless hash.is_a?(Hash)

    decrypt_fields(hash)
  end

  def serialize(value)
    hash = value.is_a?(Hash) ? value.deep_dup : {}
    encrypt_fields(hash)
    super(hash)
  end

  private

  def resolve_sensitive_keys(hash)
    if @sensitive_keys_config.respond_to?(:call)
      Array(@sensitive_keys_config.call(hash)).map(&:to_s)
    else
      Array(@sensitive_keys_config).map(&:to_s)
    end
  end

  def decrypt_fields(hash)
    resolve_sensitive_keys(hash).each do |key|
      next if hash[key].blank?

      hash[key] = ActiveRecord::Encryption.encryptor.decrypt(hash[key])
    rescue ActiveRecord::Encryption::Errors::Decryption
      hash[key] = nil
    rescue StandardError
      # Keep raw value
    end
    hash
  end

  def encrypt_fields(hash)
    resolve_sensitive_keys(hash).each do |key|
      next if hash[key].blank?

      hash[key] = ActiveRecord::Encryption.encryptor.encrypt(hash[key].to_s)
    end
  end
end
