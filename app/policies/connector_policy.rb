# frozen_string_literal: true

class ConnectorPolicy < ApplicationPolicy
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

  def fetch_bot_info?
    admin_with_record_access?
  end

  def setup_webhook?
    admin_with_record_access?
  end

  def transport_fields?
    admin_with_record_access?
  end

  def provider_fields?
    admin_with_record_access?
  end
end
