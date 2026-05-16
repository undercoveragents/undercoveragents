# frozen_string_literal: true

class CreateConnectorsTelegrams < ActiveRecord::Migration[8.1]
  def change
    create_table :connectors_telegrams do |t|
      t.text :bot_token, null: false
      t.string :bot_username
      t.string :webhook_url
      t.string :webhook_secret

      t.timestamps
    end
  end
end
