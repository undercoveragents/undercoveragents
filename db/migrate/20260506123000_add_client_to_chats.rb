# frozen_string_literal: true

class AddClientToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :client, foreign_key: true
  end
end
