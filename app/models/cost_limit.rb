# frozen_string_literal: true

# == Schema Information
#
# Table name: cost_limits
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  amount_usd                :decimal(18, 6)   not null
#  description               :text
#  enabled                   :boolean          default(TRUE), not null
#  enforcement_mode          :string           default("warn_only"), not null
#  name                      :string           not null
#  period                    :string           not null
#  target_key                :string
#  target_type               :string           not null
#  warning_threshold_percent :integer          default(80), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  operation_id              :bigint
#  target_id                 :bigint
#  tenant_id                 :bigint           not null
#
# Indexes
#
#  idx_cost_limits_on_target                        (tenant_id,target_type,target_id,target_key)
#  index_cost_limits_on_operation_id                (operation_id)
#  index_cost_limits_on_tenant_id                   (tenant_id)
#  index_cost_limits_on_tenant_id_and_enabled       (tenant_id,enabled)
#  index_cost_limits_on_tenant_id_and_operation_id  (tenant_id,operation_id)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
class CostLimit < ApplicationRecord
  TARGET_TYPES = [
    "tenant",
    "operation",
    "user",
    "agent",
    "mission",
    "channel",
    "model",
    "execution_context",
  ].freeze
  PERIODS = [
    "day",
    "week",
    "month",
    "quarter",
    "year",
    "rolling_7_days",
    "rolling_30_days",
    "all_time",
  ].freeze
  ENFORCEMENT_MODES = ["warn_only", "hard_stop"].freeze

  belongs_to :tenant
  belongs_to :operation, optional: true

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(enabled: :desc, target_type: :asc, name: :asc) }

  validates :name, presence: true, length: { maximum: 120 }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :period, inclusion: { in: PERIODS }
  validates :enforcement_mode, inclusion: { in: ENFORCEMENT_MODES }
  validates :amount_usd, numericality: { greater_than: 0 }
  validates :warning_threshold_percent,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validate :target_reference_matches_type
  validate :operation_belongs_to_tenant
  validate :target_belongs_to_tenant

  def hard_stop?
    enforcement_mode == "hard_stop"
  end

  def warning_fraction
    BigDecimal(warning_threshold_percent.to_s) / 100
  end

  def target_record
    return unless TARGET_TYPES.include?(target_type)
    return tenant if target_type == "tenant"
    return operation if target_type == "operation" && operation_id.present?
    return nil if ["operation", "execution_context"].include?(target_type)
    return nil if target_id.blank?

    target_class.find_by(id: target_id)
  end

  def target_label
    return tenant.name if target_type == "tenant"
    return target_key if target_type == "execution_context"

    target_record&.try(:name) || target_record&.try(:email) || "Unknown #{target_type}"
  end

  private

  def target_reference_matches_type
    return unless TARGET_TYPES.include?(target_type)

    case target_type
    when "tenant"
      validate_tenant_target
    when "operation"
      validate_operation_target
    when "execution_context"
      validate_execution_context_target
    else
      validate_record_target
    end
  end

  def validate_tenant_target
    errors.add(:target_id, "must be blank for tenant limits") if target_id.present?
    errors.add(:target_key, "must be blank for tenant limits") if target_key.present?
  end

  def validate_operation_target
    errors.add(:operation, "must be selected for operation limits") if operation.blank?
    errors.add(:target_id, "must be blank for operation limits") if target_id.present?
    errors.add(:target_key, "must be blank for operation limits") if target_key.present?
  end

  def validate_execution_context_target
    if target_key.blank? || !Chat.execution_contexts.key?(target_key)
      errors.add(:target_key, "must be a valid execution context")
    end
    errors.add(:target_id, "must be blank for execution context limits") if target_id.present?
  end

  def validate_record_target
    errors.add(:target_id, "must be selected for #{target_type} limits") if target_id.blank?
    errors.add(:target_key, "must be blank for #{target_type} limits") if target_key.present?
    return if target_id.blank? || target_class.exists?(target_id)

    errors.add(:target_id, "does not reference an existing #{target_type}")
  end

  def operation_belongs_to_tenant
    return if operation.blank? || tenant.blank? || operation.tenant_id == tenant_id

    errors.add(:operation, "must belong to the same tenant")
  end

  def target_belongs_to_tenant
    record = target_record
    return if record.blank? || tenant.blank?
    return if tenant_id_for_target(record) == tenant_id

    errors.add(:target_id, "must belong to the same tenant")
  end

  def tenant_id_for_target(record)
    return record.id if record.is_a?(Tenant)
    return record.tenant_id if record.respond_to?(:tenant_id)
    return record.operation.tenant_id if record.respond_to?(:operation) && record.operation

    tenant_id
  end

  def target_class
    {
      "user" => User,
      "agent" => Agent,
      "mission" => Mission,
      "channel" => Channel,
      "model" => Model,
    }.fetch(target_type)
  end
end
