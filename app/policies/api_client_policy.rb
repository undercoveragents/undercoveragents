# frozen_string_literal: true

class ApiClientPolicy < ApplicationPolicy
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
    admin_with_record_access?
  end

  def destroy?
    admin_with_record_access?
  end

  def toggle?
    admin_with_record_access?
  end

  def regenerate_token?
    admin_with_record_access?
  end
end
