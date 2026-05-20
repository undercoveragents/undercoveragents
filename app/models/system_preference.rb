# frozen_string_literal: true

# == Schema Information
#
# Table name: system_preferences
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  custom_llm_params      :jsonb            not null
#  model_routing_config   :jsonb            not null
#  temperature            :float
#  thinking_budget        :integer
#  thinking_effort        :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  embedding_connector_id :bigint
#  embedding_model_id     :string
#  image_connector_id     :bigint
#  image_model_id         :string
#  llm_connector_id       :bigint
#  model_id               :string
#  tenant_id              :bigint           not null
#
# Indexes
#
#  index_system_preferences_on_tenant_id  (tenant_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (embedding_connector_id => connectors.id)
#  fk_rails_...  (image_connector_id => connectors.id)
#  fk_rails_...  (llm_connector_id => connectors.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
class SystemPreference < ApplicationRecord
  include SystemPreferenceLlmOptions

  DEFAULT_TEMPERATURE = SystemPreferenceLlmOptions::DEFAULT_TEMPERATURE

  belongs_to :tenant
  belongs_to :llm_connector, class_name: "Connector", optional: true
  belongs_to :embedding_connector, class_name: "Connector", optional: true
  belongs_to :image_connector, class_name: "Connector", optional: true

  validates :tenant, uniqueness: true
  validate :llm_connector_must_be_llm_provider
  validate :model_must_be_present_with_connector
  validate :embedding_connector_must_be_llm_provider
  validate :embedding_model_must_be_present_with_connector
  validate :image_connector_must_be_llm_provider
  validate :image_model_must_be_present_with_connector
  validate :connectors_must_belong_to_tenant

  before_validation :assign_default_tenant, on: :create
  after_commit :invalidate_cache

  # Returns the singleton instance, creating it if needed.
  def self.current(tenant: Current.tenant || Tenant.default_tenant)
    raise "Tenant is required to resolve system preferences" if tenant.blank?

    find_or_create_by!(tenant:)
  end

  # Returns a cached hash of the current preferences.
  def self.current_settings(tenant: Current.tenant || Tenant.default_tenant)
    return {} if tenant.blank?

    Rails.cache.fetch(cache_key(tenant)) { build_settings_payload(tenant) }
  end

  def self.invalidate_cache!(tenant = nil)
    return Rails.cache.delete_matched("system_preferences/*/current") if tenant.nil?

    Rails.cache.delete(cache_key(tenant))
  end

  # Returns true if a usable default model is configured.
  def self.llm_configured?(tenant: Current.tenant || Tenant.default_tenant)
    settings = current_settings(tenant:)
    settings[:llm_connector_id].present? && settings[:model_id].present?
  end

  def self.cache_key(tenant)
    "system_preferences/#{tenant.id}/current"
  end

  # Builds a RubyLLM context from the configured connector.
  def resolve_llm_context
    return nil if llm_connector_id.blank?

    llm_connector&.configurator&.build_context
  end

  def resolve_embedding_context
    return nil if embedding_connector_id.blank?

    embedding_connector&.configurator&.build_context
  end

  def resolve_image_context
    return nil if image_connector_id.blank?

    image_connector&.configurator&.build_context
  end

  def configured?
    llm_connector_id.present? && model_id.present?
  end

  def embedding_configured?
    embedding_connector_id.present? && embedding_model_id.present?
  end

  def image_configured?
    image_connector_id.present? && image_model_id.present?
  end

  private_class_method def self.build_settings_payload(tenant)
    pref = find_by(tenant:)
    return {} unless pref

    {
      llm_connector_id: pref.llm_connector_id,
      model_id: pref.model_id,
      temperature: pref.temperature,
      thinking_effort: pref.thinking_effort,
      thinking_budget: pref.thinking_budget,
      custom_llm_params: pref.custom_llm_params,
      model_routing_config: pref.model_routing_config,
      embedding_connector_id: pref.embedding_connector_id,
      embedding_model_id: pref.embedding_model_id,
      image_connector_id: pref.image_connector_id,
      image_model_id: pref.image_model_id,
    }
  end

  private

  def llm_connector_must_be_llm_provider
    return if llm_connector_id.blank?
    return if llm_connector&.connector_type == "llm_provider"

    errors.add(:llm_connector_id, "must be an LLM Provider connector")
  end

  def model_must_be_present_with_connector
    return if llm_connector_id.blank?
    return if model_id.present?

    errors.add(:model_id, "must be selected when a connector is configured")
  end

  def embedding_connector_must_be_llm_provider
    return if embedding_connector_id.blank?
    return if embedding_connector&.connector_type == "llm_provider"

    errors.add(:embedding_connector_id, "must be an LLM Provider connector")
  end

  def embedding_model_must_be_present_with_connector
    return if embedding_connector_id.blank?
    return if embedding_model_id.present?

    errors.add(:embedding_model_id, "must be selected when a connector is configured")
  end

  def image_connector_must_be_llm_provider
    return if image_connector_id.blank?
    return if image_connector&.connector_type == "llm_provider"

    errors.add(:image_connector_id, "must be an LLM Provider connector")
  end

  def image_model_must_be_present_with_connector
    return if image_connector_id.blank?
    return if image_model_id.present?

    errors.add(:image_model_id, "must be selected when a connector is configured")
  end

  def invalidate_cache
    self.class.invalidate_cache!(tenant)
  end

  def assign_default_tenant
    self.tenant ||= Current.tenant || Tenant.default_tenant
  end

  def connectors_must_belong_to_tenant
    {
      llm_connector:,
      embedding_connector:,
      image_connector:,
    }.each do |attribute, connector|
      next if connector.blank? || connector.tenant_id == tenant_id

      errors.add(attribute, "must belong to the same tenant")
    end
  end
end
