# frozen_string_literal: true

class SystemPreferencePolicy < ApplicationPolicy
  def show?
    admin_with_record_access?
  end

  def update?
    admin_with_record_access?
  end
end
