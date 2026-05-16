# frozen_string_literal: true

class SkillCatalogPolicy < ApplicationPolicy
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

  def restore?
    operation_mutation_allowed? || headquarter_builtin_restore_allowed?
  end

  def restore_defaults? = headquarter_maintenance_allowed?(SkillCatalog)

  def destroy?
    operation_mutation_allowed?
  end

  def import?
    operation_mutation_allowed?
  end

  def create_import?
    operation_mutation_allowed?
  end

  def attach_agent?
    operation_mutation_allowed?
  end

  def detach_agent?
    operation_mutation_allowed?
  end

  private

  def headquarter_builtin_restore_allowed?
    record.builtin? && headquarter_maintenance_allowed?
  end
end
