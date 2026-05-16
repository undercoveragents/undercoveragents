# frozen_string_literal: true

class OperationPolicy < ApplicationPolicy
  def index?
    admin_user?
  end

  def show?
    admin_with_record_access?
  end

  def create?
    admin_with_record_access?
  end

  def update?
    admin_with_record_access? && !record.headquarter?
  end

  def destroy?
    admin_with_record_access? && !record.headquarter?
  end

  def switch?
    admin_with_record_access?
  end
end
