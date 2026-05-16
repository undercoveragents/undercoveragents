# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_credentials
# Database name: primary
#
#  id              :bigint           not null, primary key
#  credential_type :string           default("bearer_token"), not null
#  enabled         :boolean          default(TRUE), not null
#  last_used_at    :datetime
#  metadata        :jsonb            not null
#  name            :string           not null
#  token_digest    :string           not null
#  token_prefix    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  channel_id      :bigint           not null
#
# Indexes
#
#  index_channel_credentials_on_channel_id           (channel_id)
#  index_channel_credentials_on_channel_id_and_name  (channel_id,name) UNIQUE
#  index_channel_credentials_on_enabled              (enabled)
#  index_channel_credentials_on_token_prefix         (token_prefix) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#
class ChannelCredential < ApplicationRecord
  TOKEN_PREFIX = "ch_"
  TOKEN_BYTE_LENGTH = 32

  attr_reader :raw_token

  enum :credential_type, { bearer_token: "bearer_token" }, validate: true

  belongs_to :channel

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }
  validates :name, presence: true, uniqueness: { scope: :channel_id, case_sensitive: false }, length: { maximum: 120 }
  validates :token_prefix, presence: true, uniqueness: true
  validates :token_digest, presence: true

  attribute :metadata, :jsonb, default: -> { {} }

  before_validation :ensure_metadata
  before_validation :ensure_token

  def self.generate_token
    raw = SecureRandom.hex(TOKEN_BYTE_LENGTH)
    prefix = "#{TOKEN_PREFIX}#{raw[0, 8]}"
    token = "#{TOKEN_PREFIX}#{raw}"
    digest = Digest::SHA256.hexdigest(token)
    { raw_token: token, prefix:, digest: }
  end

  def self.authenticate(raw_token, channel: nil, tenant: nil)
    return nil if raw_token.blank? || !raw_token.start_with?(TOKEN_PREFIX)

    credential = enabled.includes(channel: :tenant).find_by(token_prefix: token_prefix_for(raw_token))
    return nil unless credential
    return nil unless matches_scope?(credential, channel:, tenant:)
    return nil unless matches_token?(credential, raw_token)

    credential.touch(:last_used_at)
    credential
  end

  def self.token_prefix_for(raw_token)
    "#{TOKEN_PREFIX}#{raw_token.delete_prefix(TOKEN_PREFIX)[0, 8]}"
  end

  def self.matches_scope?(credential, channel:, tenant:)
    return false if channel.present? && credential.channel_id != channel.id
    return false if tenant.present? && credential.channel.tenant_id != tenant.id

    true
  end

  def self.matches_token?(credential, raw_token)
    digest = Digest::SHA256.hexdigest(raw_token)
    ActiveSupport::SecurityUtils.secure_compare(credential.token_digest, digest)
  end

  private_class_method :token_prefix_for, :matches_scope?, :matches_token?

  def masked_token
    "#{token_prefix}#{"*" * 24}#{token_digest.last(8)}"
  end

  def regenerate_token!
    token_data = self.class.generate_token
    @raw_token = token_data[:raw_token]
    update!(token_prefix: token_data[:prefix], token_digest: token_data[:digest])
    raw_token
  end

  private

  def ensure_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def ensure_token
    return unless token_digest.nil? && token_prefix.nil?

    token_data = self.class.generate_token
    @raw_token = token_data[:raw_token]
    self.token_prefix = token_data[:prefix]
    self.token_digest = token_data[:digest]
  end
end
