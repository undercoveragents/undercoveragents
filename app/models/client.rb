# frozen_string_literal: true

# == Schema Information
#
# Table name: clients
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  name          :string           not null
#  slug          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  agent_id      :bigint           not null
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_clients_on_agent_id            (agent_id)
#  index_clients_on_default             (default)
#  index_clients_on_slug                (slug) UNIQUE
#  index_clients_on_tenant_id           (tenant_id)
#  index_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
class Client < ApplicationRecord
  extend FriendlyId
  include ClientConfiguration

  friendly_id :name, use: :slugged

  has_one_attached :logo

  belongs_to :tenant
  belongs_to :agent
  has_many :chats, dependent: :nullify

  # ── Scopes ───────────────────────────────────────────────────────────────────
  scope :ordered, -> { order(:name) }
  # ── Validations ──────────────────────────────────────────────────────────────
  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }, length: { maximum: 100 }
  validate :agent_must_be_enabled
  validate :agent_must_belong_to_tenant
  validate :must_have_one_default

  # ── Callbacks ────────────────────────────────────────────────────────────────
  before_save :sanitize_rich_fields
  after_commit :invalidate_cache

  # ── Class Methods ────────────────────────────────────────────────────────────

  # Returns a lightweight, cached hash of the current default client's settings.
  # Avoids hitting the DB on every request.
  def self.current_settings(tenant: Current.tenant || Tenant.default_tenant)
    return nil if tenant.blank?

    Rails.cache.fetch(cache_key(tenant)) { build_settings_payload(tenant) }
  end

  def self.invalidate_settings_cache!(tenant = nil)
    return Rails.cache.delete_matched("client/*/default_settings") if tenant.nil?

    Rails.cache.delete(cache_key(tenant))
  end

  def settings_payload
    logo_url = (Rails.application.routes.url_helpers.rails_blob_path(logo, only_path: true) if logo.attached?)

    {
      id:,
      name:,
      title:,
      welcome_message:,
      footer:,
      labels: effective_label_settings,
      agent_id:,
      agent_name: agent&.name,
      logo_url:,
    }
  end

  def self.cache_key(tenant)
    "client/#{tenant.id}/default_settings"
  end

  private_class_method :cache_key

  ALLOWED_TAGS = [
    "p", "br", "strong", "em", "b", "i", "u", "s", "a", "ul", "ol", "li",
    "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "code", "pre", "span", "sub", "sup",
  ].freeze
  ALLOWED_ATTRIBUTES = ["href", "target", "rel", "class"].freeze

  private_constant :ALLOWED_TAGS, :ALLOWED_ATTRIBUTES

  private

  def self.build_settings_payload(tenant)
    client = tenant.clients.where(default: true).includes(:agent).order(:id).first
    client&.settings_payload
  end

  def sanitize_rich_fields
    sanitizer = Rails::HTML5::SafeListSanitizer.new
    [:title, :welcome_message, :footer].each do |field|
      value = public_send(field)
      next if value.blank?

      public_send("#{field}=", sanitizer.sanitize(value, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES))
    end
  end

  def agent_must_be_enabled
    return if agent.blank?

    errors.add(:agent, "must be enabled") unless agent.enabled?
    errors.add(:agent, "must be selectable") unless agent.selectable?
  end

  def agent_must_belong_to_tenant
    return if agent.blank? || tenant.blank?
    return if agent.operation.tenant_id == tenant_id

    errors.add(:agent, "must belong to the same tenant")
  end

  def must_have_one_default
    return unless default_changed? && !default?

    other_default = self.class.where(tenant_id:, default: true).where.not(id:).exists?
    errors.add(:default, "cannot be removed — at least one default client is required") unless other_default
  end

  def invalidate_cache
    self.class.invalidate_settings_cache!(tenant)
  end

  private_class_method :build_settings_payload
end
