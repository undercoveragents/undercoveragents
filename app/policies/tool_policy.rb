# frozen_string_literal: true

class ToolPolicy < ApplicationPolicy
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

  def clone?
    operation_mutation_allowed?
  end

  def destroy?
    operation_mutation_allowed?
  end

  def toggle?
    operation_mutation_allowed?
  end

  def discover_schema?
    operation_mutation_allowed?
  end

  def edit_visibility?
    operation_mutation_allowed?
  end

  def update_visibility?
    operation_mutation_allowed?
  end
end
