# frozen_string_literal: true

# == Schema Information
#
# Table name: channels
# Database name: primary
#
#  id            :bigint           not null, primary key
#  channel_type  :string           not null
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  connector_id  :bigint
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_channels_on_channel_type        (channel_type)
#  index_channels_on_connector_id        (connector_id)
#  index_channels_on_default             (default)
#  index_channels_on_enabled             (enabled)
#  index_channels_on_slug                (slug) UNIQUE
#  index_channels_on_tenant_id           (tenant_id)
#  index_channels_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
class Channel < ApplicationRecord
  extend FriendlyId

  friendly_id :name, use: :slugged

  has_one_attached :logo

  belongs_to :tenant
  belongs_to :connector, optional: true

  has_many :channel_targets, dependent: :destroy
  has_many :channel_identities, dependent: :destroy
  has_many :channel_conversations, dependent: :destroy
  has_many :channel_credentials, dependent: :destroy
  has_many :chats, dependent: :nullify
  has_many :mission_runs, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :by_type, ->(type) { where(channel_type: type) }
  scope :ordered, -> { order(:name) }
  scope :for_tenant, ->(tenant) { where(tenant:) }
  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }
  validates :channel_type, presence: true
  validate :channel_type_registered
  validate :connector_must_belong_to_tenant
  validate :connector_must_match_channel_type

  attribute :configuration, :jsonb, default: -> { {} }

  before_validation :ensure_configuration
  before_validation :validate_configurator
  before_save :apply_configurator_before_save
  after_commit :invalidate_client_settings_cache

  def self.current_client_channel(tenant: Current.tenant || Tenant.default_tenant)
    return nil if tenant.blank?

    Rails.cache.fetch(client_settings_cache_key(tenant)) do
      tenant.channels.includes(channel_targets: :target)
            .enabled
            .by_type("client")
            .where(default: true)
            .ordered
            .first || tenant.channels.includes(channel_targets: :target).enabled.by_type("client").ordered.first
    end
  end

  def self.current_client_settings(tenant: Current.tenant || Tenant.default_tenant)
    current_client_channel(tenant:)&.settings_payload
  end

  def self.invalidate_client_settings_cache!(tenant = nil)
    return Rails.cache.delete_matched("channel/*/default_client_settings") if tenant.nil?

    Rails.cache.delete(client_settings_cache_key(tenant))
  end

  def configurator
    return @configurator if @configurator && @configurator_built_for_type == channel_type

    @configurator = build_configurator
  end

  def configuration=(value)
    super
    @configurator = nil
    @configurator_built_for_type = nil
  end

  def reload(*)
    @configurator = nil
    @configurator_built_for_type = nil
    super
  end

  def method_missing(method_name, ...)
    if configurator.respond_to?(method_name)
      configurator.public_send(method_name, ...)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    configurator.respond_to?(method_name, include_private) || super
  end

  def type_label
    ChannelPlugin.label_for(channel_type) || channel_type.to_s.titleize
  end

  def type_icon
    ChannelPlugin.icon_for(channel_type) || "fa-solid fa-tower-broadcast"
  end

  def client_channel?
    channel_type == "client"
  end

  def api_channel?
    channel_type == "api"
  end

  def allowed_target_kinds
    configurator&.class&.target_kinds || []
  end

  def default_target
    channel_targets.defaults.ordered.first || channel_targets.ordered.first
  end

  def client_agent
    target = default_target
    target.target if target&.target_type == "Agent"
  end

  def settings_payload
    return unless client_channel?

    configurator&.settings_payload(channel: self)
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  private

  def self.client_settings_cache_key(tenant)
    "channel/#{tenant.id}/default_client_settings"
  end
  private_class_method :client_settings_cache_key

  def build_configurator
    @configurator_built_for_type = channel_type
    klass = ChannelPlugin.resolve(channel_type)
    return nil unless klass

    instance = klass.new(configurator_attributes_for(klass))
    instance._channel_record = self
    instance
  rescue StandardError
    nil
  end

  def configurator_attributes_for(klass)
    attributes = (configuration || {}).symbolize_keys
    return attributes unless klass.respond_to?(:attribute_types)

    attributes.slice(*klass.attribute_types.keys.map(&:to_sym))
  end

  def channel_type_registered
    return if channel_type.blank?
    return if ChannelPlugin.type_keys.include?(channel_type)

    errors.add(:channel_type, "is not a registered channel type")
  end

  def connector_must_belong_to_tenant
    return if connector.blank? || tenant.blank?
    return if connector.tenant_id == tenant_id

    errors.add(:connector, "must belong to the same tenant")
  end

  def connector_must_match_channel_type
    required_type = configurator&.class&.requires_connector_type
    return if required_type.blank? || connector.blank?
    return if connector.connector_type == required_type

    errors.add(:connector, "must be a #{required_type.tr("_", " ")} connector")
  end

  def validate_configurator
    return unless configurator
    return if configurator.valid?

    configurator.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end

  def apply_configurator_before_save
    return unless configurator

    self.configuration = configurator.to_configuration
  end

  def ensure_configuration
    self.configuration = {} unless configuration.is_a?(Hash)
  end

  def invalidate_client_settings_cache
    self.class.invalidate_client_settings_cache!(tenant)
  end
end
