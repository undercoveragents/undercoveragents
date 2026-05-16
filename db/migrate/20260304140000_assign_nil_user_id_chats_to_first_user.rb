# frozen_string_literal: true

class AssignNilUserIdChatsToFirstUser < ActiveRecord::Migration[8.1]
  def up
    first_user_id = execute("SELECT id FROM users ORDER BY id ASC LIMIT 1").first&.fetch("id")
    return unless first_user_id

    execute("UPDATE chats SET user_id = #{first_user_id} WHERE user_id IS NULL")
  end

  def down
    # Irreversible — cannot determine which chats originally had nil user_id
  end
end
