# frozen_string_literal: true

class CreateConnectorsAuthentications < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_authentications do |t|
      t.string :provider, null: false
      t.string :site_url
      t.string :realm
      t.string :client_id
      t.text :client_secret

      t.timestamps
    end
  end
end
