class CreateAgentTools < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_tools do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :tool, null: false, foreign_key: true
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :agent_tools, [:agent_id, :tool_id], unique: true
  end
end
