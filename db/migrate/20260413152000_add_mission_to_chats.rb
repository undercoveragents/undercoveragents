# frozen_string_literal: true

class AddMissionToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :mission, foreign_key: true
  end
end
