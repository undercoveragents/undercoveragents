# frozen_string_literal: true

class RagFlowPolicy < ApplicationPolicy
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

  def destroy?
    operation_mutation_allowed?
  end

  def toggle?
    operation_mutation_allowed?
  end

  def execute?
    operation_mutation_allowed? && record.enabled? && record.runnable?
  end
end
