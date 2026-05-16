class DropConnectorsVectorDatabases < ActiveRecord::Migration[8.1]
  def up
    drop_table :connectors_vector_databases
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
