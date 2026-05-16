# frozen_string_literal: true

class CreateArchivalMemories < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector" unless extension_enabled?("vector")

    create_table :archival_memories do |t|
      t.references :agent,     null: false, foreign_key: true
      t.text       :content,   null: false
      t.column     :embedding, :vector, limit: 1536
      t.string     :tags,      array: true, null: false, default: []

      t.timestamps
    end

    add_index :archival_memories, :tags, using: :gin
  end
end
