# frozen_string_literal: true

class ApplicationPolicy
  HEADQUARTER_READ_ONLY_MESSAGE = "Headquarter is read-only. Switch to another operation to create or modify records."
  MUTATION_QUERIES = [
    :create?,
    :new?,
    :update?,
    :edit?,
    :destroy?,
    :toggle?,
    :restore?,
    :restore_defaults?,
    :discover_schema?,
    :edit_visibility?,
    :update_visibility?,
    :import?,
    :create_import?,
    :attach_agent?,
    :detach_agent?,
    :execute?,
    :designer?,
  ].freeze
  OPERATION_ASSOCIATIONS = [:skill_catalog, :agent, :mission].freeze

  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def denied_reason(query)
    return HEADQUARTER_READ_ONLY_MESSAGE if mutation_query?(query) && headquarter_read_only_target?

    return if public_send(query)

    "You do not have permission to do that."
  end

  private

  def admin_user?
    !!user&.admin?
  end

  def system_admin?
    !!user&.system_admin?
  end

  def admin_with_record_access?(target = record)
    return false unless admin_user?

    tenant_id = tenant_id_for(target)
    tenant_id ||= current_context_tenant_id(target) if target.nil? || target.is_a?(Class) || target_new_record?(target)

    tenant_id.present? && tenant_id == user.tenant_id
  end

  def tenant_id_for(target = record)
    return if target.nil?

    direct_tenant_id_for(target) || nested_tenant_id_for(target)
  end

  def current_context_tenant_id(target = record)
    Current.tenant&.id || tenant_id_for(operation_for(target))
  end

  def target_new_record?(target)
    target.respond_to?(:new_record?) && target.new_record?
  end

  def direct_tenant_id_for(target)
    return target.tenant_id if target.respond_to?(:tenant_id) && target.tenant_id.present?
    return target.tenant.id if target.respond_to?(:tenant) && target.tenant.present?

    nil
  end

  def nested_tenant_id_for(target)
    [:operation, :skill_catalog, :agent, :mission, :test_suite].each do |association|
      next unless target.respond_to?(association)

      child = target.public_send(association)
      return tenant_id_for(child) if child.present?
    end

    nil
  end

  def operation_mutation_allowed?(target = record)
    admin_with_record_access?(target) && !headquarter_read_only_target?(target)
  end

  def headquarter_maintenance_allowed?(target_class = nil, target = record)
    return false if target_class.present? && target != target_class

    admin_with_record_access?(target) && headquarter_read_only_target?(target)
  end

  def headquarter_read_only_target?(target = record)
    operation_for(target)&.headquarter? || false
  end

  def operation_for(target = record)
    return Current.operation if target.nil? || target.is_a?(Class)
    return target if target.is_a?(Operation)

    operation_from_target(target) || operation_from_associations(target) || new_record_operation(target)
  end

  def mutation_query?(query)
    query.to_sym.in?(MUTATION_QUERIES)
  end

  def operation_from_target(target)
    return unless target.respond_to?(:operation)

    target.operation.presence
  end

  def operation_from_associations(target)
    OPERATION_ASSOCIATIONS.lazy.filter_map do |association|
      associated_operation_for(target, association)
    end.first
  end

  def associated_operation_for(target, association)
    return unless target.respond_to?(association)

    associated_record = target.public_send(association)
    return unless associated_record.respond_to?(:operation)

    associated_record.operation.presence
  end

  def new_record_operation(target)
    Current.operation if target.respond_to?(:new_record?) && target.new_record?
  end
end
