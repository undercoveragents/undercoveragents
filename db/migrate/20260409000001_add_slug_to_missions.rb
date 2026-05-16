# frozen_string_literal: true

class AddSlugToMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :missions, :slug, :string
    add_index :missions, :slug, unique: true
  end
end
