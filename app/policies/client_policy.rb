# frozen_string_literal: true

class ClientPolicy < ApplicationPolicy
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
    admin_with_record_access? && other_clients_exist_in_tenant?
  end

  private

  def other_clients_exist_in_tenant?
    tenant_id = tenant_id_for(record)
    return false if tenant_id.blank?

    Client.where(tenant_id:).where.not(id: record.id).exists?
  end
end
