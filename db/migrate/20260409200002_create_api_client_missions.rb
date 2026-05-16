# frozen_string_literal: true

class CreateApiClientMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :api_client_missions do |t|
      t.references :api_client, null: false, foreign_key: true
      t.references :mission, null: false, foreign_key: true

      t.timestamps
    end

    add_index :api_client_missions, [:api_client_id, :mission_id], unique: true
  end
end
