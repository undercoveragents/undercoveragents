# frozen_string_literal: true

class SkillPolicy < ApplicationPolicy
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

  def destroy?
    operation_mutation_allowed?
  end

  private

  def headquarter_builtin_restore_allowed?
    return false unless record.builtin? && record.skill_catalog&.builtin?

    headquarter_maintenance_allowed?
  end
end
