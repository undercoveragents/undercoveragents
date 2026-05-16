# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    admin_user?
  end

  def create?
    manageable_user?
  end

  def update?
    manageable_user?
  end

  def destroy?
    manageable_user?
  end

  private

  def manageable_user?
    return false unless admin_with_record_access?
    return true if system_admin?

    !record.system_admin?
  end
end
