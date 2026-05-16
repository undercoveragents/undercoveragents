# frozen_string_literal: true

class TenantPolicy < ApplicationPolicy
  def index?
    !!user&.system_admin?
  end

  def create?
    !!user&.system_admin?
  end

  def update?
    !!user&.system_admin?
  end

  def destroy?
    !!user&.system_admin?
  end
end
