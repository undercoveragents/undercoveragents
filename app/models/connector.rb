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
#  enabled        :boolean          default(TRUE), not null
#  name           :string           not null
#  slug           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  tenant_id      :bigint           not null
#
# Indexes
#
#  index_connectors_on_connector_type      (connector_type)
#  index_connectors_on_enabled             (enabled)
#  index_connectors_on_slug                (slug) UNIQUE
#  index_connectors_on_tenant_id           (tenant_id)
#  index_connectors_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
class Connector < ApplicationRecord
  extend FriendlyId

  belongs_to :tenant
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :by_type, ->(type) { where(connector_type: type) }
  scope :ordered, -> { order(:name) }
  scope :for_tenant, ->(tenant) { where(tenant:) }
  # Convenience type scopes
  scope :llm_providers, -> { by_type("llm_provider") }
  scope :sql_databases, -> { by_type("sql_database") }
  scope :mcp_servers, -> { by_type("mcp_server") }
  scope :authentications, -> { by_type("authentication") }
  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }
  validates :connector_type, presence: true
  validate :connector_type_registered
  before_validation :ensure_configuration
  before_validation :validate_configurator
  before_save :apply_configurator_before_save
  before_update :notify_configurator_of_changes
  def self.policy_class = ConnectorPolicy

  friendly_id :name, use: :slugged

  attribute :configuration, EncryptedConfigurationJsonType.new(
    sensitive_keys: ->(hash) { Connector.sensitive_keys_for_hash(hash) },
  ), default: -> { {} }

  # Returns an ActiveModel configurator instance for the connector_type,
  # hydrated with the JSONB configuration attributes. Uses stable caching
  # that only rebuilds when the connector_type actually changes, so that
  # incremental attribute assignments through method_missing are preserved.
  def configurator
    return @configurator if @configurator && @configurator_built_for_type == connector_type

    @configurator = build_configurator
  end

  # Invalidate cached configurator when configuration is directly assigned,
  # so the next access rebuilds from the new JSONB values.
  def configuration=(value)
    super
    @configurator = nil
    @configurator_built_for_type = nil
  end

  # Invalidate cached configurator on reload so it rebuilds from DB values.
  def reload(*)
    @configurator = nil
    @configurator_built_for_type = nil
    super
  end

  # Delegate type-specific methods to the configurator
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
    ConnectorPlugin.label_for(connector_type) || connector_type.to_s.titleize
  end

  def type_icon
    ConnectorPlugin.icon_for(connector_type) || "fa-solid fa-plug"
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  # Resolve sensitive keys from connector_type for the encryption layer.
  def self.sensitive_keys_for_hash(_hash)
    @all_sensitive_keys ||= nil
    return @all_sensitive_keys if @all_sensitive_keys

    keys = []
    ConnectorPlugin.type_keys.each do |type_key|
      klass = ConnectorPlugin.resolve(type_key)
      keys.concat(klass.sensitive_keys) if klass.respond_to?(:sensitive_keys)
    # :nocov:
    rescue NameError
      next
      # :nocov:
    end
    @all_sensitive_keys = keys.uniq
  # :nocov:
  rescue StandardError
    []
    # :nocov:
  end

  def self.reset_sensitive_keys_cache!
    @all_sensitive_keys = nil
  end

  private

  def build_configurator
    @configurator_built_for_type = connector_type
    klass = ConnectorPlugin.resolve(connector_type)
    return nil unless klass

    inst = klass.new((configuration || {}).symbolize_keys)
    inst._connector_record = self
    inst
  # :nocov:
  rescue StandardError
    nil
    # :nocov:
  end

  def connector_type_registered
    return if connector_type.blank?
    return if ConnectorPlugin.type_keys.include?(connector_type)

    errors.add(:connector_type, "is not a registered connector type")
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

  def notify_configurator_of_changes
    return unless configurator.respond_to?(:on_configuration_change)
    return unless will_save_change_to_configuration?

    old_config, new_config = configuration_change_to_be_saved
    configurator.on_configuration_change(self, old_config, new_config)
  end
end
