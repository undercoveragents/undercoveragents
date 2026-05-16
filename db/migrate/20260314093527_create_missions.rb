class CreateMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :missions do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :flow_data, default: { "nodes" => [], "edges" => [] }, null: false

      t.timestamps
    end

    add_index :missions, :name
  end
end
