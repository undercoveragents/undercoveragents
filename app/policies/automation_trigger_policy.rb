# frozen_string_literal: true

class AutomationTriggerPolicy < ApplicationPolicy
  def index?
    admin_with_record_access?
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

  def destroy?
    operation_mutation_allowed?
  end

  def regenerate_secret?
    update?
  end
end
