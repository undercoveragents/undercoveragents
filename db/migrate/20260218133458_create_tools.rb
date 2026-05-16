class CreateTools < ActiveRecord::Migration[8.1]
  def change
    create_table :tools do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, default: false, null: false
      t.string :toolable_type, null: false
      t.bigint :toolable_id, null: false

      t.timestamps
    end

    add_index :tools, :name, unique: true
    add_index :tools, [:toolable_type, :toolable_id], unique: true
    add_index :tools, :enabled
  end
end
