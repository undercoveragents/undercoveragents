# frozen_string_literal: true

class CreateTenantsAndScopeGlobalResources < ActiveRecord::Migration[8.1]
  class MigrationTenant < ApplicationRecord
    self.table_name = "tenants"
  end

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationOperation < ApplicationRecord
    self.table_name = "operations"
  end

  class MigrationConnector < ApplicationRecord
    self.table_name = "connectors"
  end

  class MigrationClient < ApplicationRecord
    self.table_name = "clients"
  end

  class MigrationApiClient < ApplicationRecord
    self.table_name = "api_clients"
  end

  class MigrationSystemPreference < ApplicationRecord
    self.table_name = "system_preferences"
  end

  def up
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      t.timestamps
    end

    add_index :tenants, :name, unique: true
    add_index :tenants, :slug, unique: true

    add_reference :operations, :tenant, foreign_key: true
    add_reference :users, :tenant, foreign_key: true
    add_reference :connectors, :tenant, foreign_key: true
    add_reference :clients, :tenant, foreign_key: true
    add_reference :api_clients, :tenant, foreign_key: true
    add_reference :system_preferences, :tenant, foreign_key: true, index: false

    MigrationTenant.reset_column_information
    MigrationUser.reset_column_information
    MigrationOperation.reset_column_information
    MigrationConnector.reset_column_information
    MigrationClient.reset_column_information
    MigrationApiClient.reset_column_information
    MigrationSystemPreference.reset_column_information

    default_tenant = MigrationTenant.create!(
      name: "Default Tenant",
      slug: "default-tenant",
      description: "Tenant created while migrating existing data to tenant isolation.",
    )

    MigrationOperation.update_all(tenant_id: default_tenant.id)
    MigrationUser.update_all(tenant_id: default_tenant.id)
    MigrationConnector.update_all(tenant_id: default_tenant.id)
    MigrationClient.update_all(tenant_id: default_tenant.id)
    MigrationApiClient.update_all(tenant_id: default_tenant.id)
    MigrationSystemPreference.update_all(tenant_id: default_tenant.id)
    MigrationUser.where(role: "admin").update_all(role: "system_admin")

    change_column_null :operations, :tenant_id, false
    change_column_null :users, :tenant_id, false
    change_column_null :connectors, :tenant_id, false
    change_column_null :clients, :tenant_id, false
    change_column_null :api_clients, :tenant_id, false
    change_column_null :system_preferences, :tenant_id, false

    remove_index :operations, :name
    add_index :operations, [:tenant_id, :name], unique: true, name: "index_operations_on_tenant_id_and_name"

    remove_index :connectors, :name
    add_index :connectors, [:tenant_id, :name], unique: true, name: "index_connectors_on_tenant_id_and_name"

    remove_index :clients, :name
    add_index :clients, [:tenant_id, :name], unique: true, name: "index_clients_on_tenant_id_and_name"

    remove_index :api_clients, :name
    add_index :api_clients, [:tenant_id, :name], unique: true, name: "index_api_clients_on_tenant_id_and_name"

    add_index :system_preferences, :tenant_id, unique: true

    remove_index :tools, :name
    add_index :tools, [:operation_id, :name], unique: true, name: "index_tools_on_operation_id_and_name"

    remove_index :rag_flows, :name
    add_index :rag_flows, [:operation_id, :name], unique: true, name: "index_rag_flows_on_operation_id_and_name"

    remove_index :test_suites, :name
    add_index :test_suites, :name
  end

  def down
    remove_index :test_suites, :name
    add_index :test_suites, :name, unique: true

    remove_index :rag_flows, name: "index_rag_flows_on_operation_id_and_name"
    add_index :rag_flows, :name, unique: true

    remove_index :tools, name: "index_tools_on_operation_id_and_name"
    add_index :tools, :name, unique: true

    remove_index :system_preferences, :tenant_id

    remove_index :api_clients, name: "index_api_clients_on_tenant_id_and_name"
    add_index :api_clients, :name, unique: true

    remove_index :clients, name: "index_clients_on_tenant_id_and_name"
    add_index :clients, :name, unique: true

    remove_index :connectors, name: "index_connectors_on_tenant_id_and_name"
    add_index :connectors, :name, unique: true

    remove_index :operations, name: "index_operations_on_tenant_id_and_name"
    add_index :operations, :name, unique: true

    MigrationUser.reset_column_information
    MigrationUser.where(role: "system_admin").update_all(role: "admin")

    remove_reference :system_preferences, :tenant, foreign_key: true
    remove_reference :api_clients, :tenant, foreign_key: true
    remove_reference :clients, :tenant, foreign_key: true
    remove_reference :connectors, :tenant, foreign_key: true
    remove_reference :users, :tenant, foreign_key: true
    remove_reference :operations, :tenant, foreign_key: true

    drop_table :tenants
  end
end
