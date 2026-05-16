# frozen_string_literal: true

# Active Record Encryption keys for encrypting sensitive fields (e.g. OAuth client secrets).
# In production, set these via Rails credentials or environment variables.
primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"].presence
deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"].presence
key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"].presence
configuring_from_env = [primary_key, deterministic_key, key_derivation_salt].any?(&:present?)

if Rails.env.local? || configuring_from_env
  if !Rails.env.local? && [primary_key, deterministic_key, key_derivation_salt].any?(&:blank?)
    raise "Set all AR_ENCRYPTION_* environment variables together."
  end

  Rails.application.configure do
    config.active_record.encryption.primary_key = primary_key || "dev-primary-key-event-horizon-0000"
    config.active_record.encryption.deterministic_key =
      deterministic_key || "dev-deterministic-key-event-h0"
    config.active_record.encryption.key_derivation_salt =
      key_derivation_salt || "dev-salt-event-horizon-000000"
  end
end
