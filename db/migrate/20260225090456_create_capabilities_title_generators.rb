# frozen_string_literal: true

class CreateCapabilitiesTitleGenerators < ActiveRecord::Migration[8.1]
  def change
    create_table :capabilities_title_generators do |t|
      t.integer :max_length, null: false, default: 30
      t.integer :max_turns, null: false, default: 3
      t.string :llm_config_source, null: false, default: "inherit"
      t.references :llm_connector, foreign_key: { to_table: :connectors }
      t.string :model_id
      t.float :temperature, default: 0.7
      t.timestamps
    end
  end
end
