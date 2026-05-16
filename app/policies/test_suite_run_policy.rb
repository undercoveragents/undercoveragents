# frozen_string_literal: true

class TestSuiteRunPolicy < ApplicationPolicy
  def show?
    admin_with_record_access?
  end

  def cancel?
    admin_with_record_access? && record.in_progress?
  end
end
