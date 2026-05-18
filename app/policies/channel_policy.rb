# frozen_string_literal: true

class ChannelPolicy < ApplicationPolicy
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

  def regenerate_token?
    operation_mutation_allowed?
  end

  def setup_webhook?
    operation_mutation_allowed?
  end
end
