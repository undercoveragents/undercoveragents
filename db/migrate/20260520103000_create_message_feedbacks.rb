# frozen_string_literal: true

class CreateMessageFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :message_feedbacks do |t|
      t.references :message, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :value, null: false
      t.string :category
      t.text :comment

      t.timestamps
    end

    add_index :message_feedbacks, [:message_id, :user_id], unique: true
    add_index :message_feedbacks, :value
  end
end
