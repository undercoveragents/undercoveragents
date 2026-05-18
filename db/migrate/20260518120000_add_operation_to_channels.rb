# frozen_string_literal: true

class AddOperationToChannels < ActiveRecord::Migration[8.1]
  class MigrationTenant < ApplicationRecord
    self.table_name = "tenants"

    has_many :operations,
             class_name: "AddOperationToChannels::MigrationOperation",
             foreign_key: :tenant_id,
             inverse_of: :tenant
  end

  class MigrationOperation < ApplicationRecord
    self.table_name = "operations"

    belongs_to :tenant,
               class_name: "AddOperationToChannels::MigrationTenant",
               inverse_of: :operations
  end

  class MigrationChannel < ApplicationRecord
    self.table_name = "channels"
  end

  def up
    add_reference :channels, :operation, foreign_key: true

    say_with_time "Backfilling channel operations from each tenant default operation" do
      MigrationTenant.find_each do |tenant|
        default_operation = tenant.operations.find_by(name: Operation::DEFAULT_NAME) ||
                            create_default_operation!(tenant)
        MigrationChannel.where(tenant_id: tenant.id, operation_id: nil)
                        .update_all(operation_id: default_operation.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    change_column_null :channels, :operation_id, false
    remove_index :channels, [:tenant_id, :name]
    add_index :channels, [:operation_id, :name], unique: true
  end

  def down
    remove_index :channels, [:operation_id, :name]
    add_index :channels, [:tenant_id, :name], unique: true
    remove_reference :channels, :operation, foreign_key: true
  end

  private

  def create_default_operation!(tenant)
    MigrationOperation.create!(
      tenant:,
      name: Operation::DEFAULT_NAME,
      slug: "default-tenant-#{tenant.id}",
      description: "Default workspace for your agents, missions, tools, and RAGs.",
      icon: "fa-solid fa-briefcase",
      system: false,
    )
  end
end
