class CreateAgentConnectors < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_connectors do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :connector, null: false, foreign_key: true
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :agent_connectors, [:agent_id, :connector_id], unique: true
  end
end
