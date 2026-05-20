# frozen_string_literal: true

class AgentPolicy < ApplicationPolicy
  def index?
    admin_user?
  end

  def show?
    admin_with_record_access?
  end

  def create?
    operation_mutation_allowed?
  end

  def update?
    operation_mutation_allowed?
  end

  def duplicate?
    operation_mutation_allowed?
  end

  def destroy?
    operation_mutation_allowed? && !record.builtin?
  end

  def toggle?
    operation_mutation_allowed?
  end

  def restore?
    operation_mutation_allowed? || headquarter_builtin_restore_allowed?
  end

  def restore_defaults? = headquarter_maintenance_allowed?(Agent)

  def denied_reason(query)
    if query.to_sym == :destroy? && record.respond_to?(:builtin?) && record.builtin?
      return "Built-in agents cannot be deleted."
    end

    super
  end

  private

  def headquarter_builtin_restore_allowed?
    return false unless record.respond_to?(:builtin?) && record.builtin?

    headquarter_maintenance_allowed?
  end
end
