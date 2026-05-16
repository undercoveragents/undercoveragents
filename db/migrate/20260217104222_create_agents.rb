class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.text :description
      t.text :instructions
      t.string :model_id, null: false
      t.float :temperature, default: 0.7, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps
    end

    add_index :agents, :name, unique: true
    add_index :agents, :enabled
  end
end
