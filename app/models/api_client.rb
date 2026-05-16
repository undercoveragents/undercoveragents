# frozen_string_literal: true

# == Schema Information
#
# Table name: api_clients
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_scope :string           default("all"), not null
#  description  :text
#  enabled      :boolean          default(TRUE), not null
#  last_used_at :datetime
#  name         :string           not null
#  token_digest :string           not null
#  token_prefix :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  tenant_id    :bigint           not null
#
# Indexes
#
#  index_api_clients_on_enabled             (enabled)
#  index_api_clients_on_tenant_id           (tenant_id)
#  index_api_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#  index_api_clients_on_token_prefix        (token_prefix) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
class ApiClient < ApplicationRecord
  TOKEN_PREFIX = "ua_"
  TOKEN_BYTE_LENGTH = 32

  enum :access_scope, { all: "all", scoped: "scoped" }, validate: true, prefix: :scope

  belongs_to :tenant

  has_many :api_client_missions, dependent: :destroy
  has_many :missions, through: :api_client_missions

  has_many :mission_runs, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }
  scope :for_tenant, ->(tenant) { where(tenant:) }
  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }, length: { maximum: 255 }
  validates :token_prefix, presence: true, uniqueness: true
  validates :token_digest, presence: true
  validate :missions_must_belong_to_tenant

  # Generates a new API token. Returns the raw token (shown once to the user).
  # Stores only the SHA-256 digest for verification.
  def self.generate_token
    raw = SecureRandom.hex(TOKEN_BYTE_LENGTH)
    prefix = "#{TOKEN_PREFIX}#{raw[0, 8]}"
    token = "#{TOKEN_PREFIX}#{raw}"
    digest = Digest::SHA256.hexdigest(token)
    { raw_token: token, prefix:, digest: }
  end

  # Finds and authenticates an API client by raw token.
  # Returns the client if valid, nil otherwise.
  def self.authenticate(raw_token, tenant: nil)
    return nil if raw_token.blank? || !raw_token.start_with?(TOKEN_PREFIX)

    prefix = "#{TOKEN_PREFIX}#{raw_token.delete_prefix(TOKEN_PREFIX)[0, 8]}"
    client = enabled.find_by(token_prefix: prefix)
    return nil unless client
    return nil if tenant.present? && client.tenant_id != tenant.id

    digest = Digest::SHA256.hexdigest(raw_token)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(client.token_digest, digest)

    client.touch(:last_used_at)
    client
  end

  def can_access_mission?(mission)
    return false if mission.operation.tenant_id != tenant_id
    return true if scope_all?

    api_client_missions.exists?(mission_id: mission.id)
  end

  def accessible_missions_scope
    tenant_scope = Mission.where(operation_id: tenant.operations.select(:id))
    return tenant_scope if scope_all?

    tenant_scope.where(id: missions.select(:id))
  end

  def masked_token
    "#{token_prefix}#{"*" * 24}#{token_digest.last(8)}"
  end

  # Regenerates the token. Returns the new raw token (shown once).
  def regenerate_token!
    token_data = self.class.generate_token
    update!(token_prefix: token_data[:prefix], token_digest: token_data[:digest])
    token_data[:raw_token]
  end

  private

  def missions_must_belong_to_tenant
    return if api_client_missions.empty? && missions.empty?

    invalid_scope = missions.where.not(operation_id: tenant.operations.select(:id))
    return if invalid_scope.none?

    errors.add(:mission_ids, "must belong to the same tenant")
  end
end
