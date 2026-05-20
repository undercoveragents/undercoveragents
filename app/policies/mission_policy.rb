# frozen_string_literal: true

class MissionPolicy < ApplicationPolicy
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
    operation_mutation_allowed?
  end

  def designer?
    update?
  end
end
