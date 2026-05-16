# frozen_string_literal: true

class CreateTelegramLinkRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :telegram_link_requests do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false

      t.timestamps
    end

    add_index :telegram_link_requests, [:channel_id, :user_id], unique: true
    add_index :telegram_link_requests, :token_digest, unique: true
  end
end
