# frozen_string_literal: true

class CreateCapabilitiesTelegrams < ActiveRecord::Migration[8.1]
  def change
    create_table :capabilities_telegrams do |t|
      t.bigint :telegram_connector_id, null: false
      t.text :welcome_message, default: "Welcome! I'm your AI assistant. Send me a message to start chatting, or use /help to see available commands."
      t.integer :max_history_messages, default: 50, null: false

      t.timestamps
    end

    add_foreign_key :capabilities_telegrams, :connectors, column: :telegram_connector_id
    add_index :capabilities_telegrams, :telegram_connector_id
  end
end
