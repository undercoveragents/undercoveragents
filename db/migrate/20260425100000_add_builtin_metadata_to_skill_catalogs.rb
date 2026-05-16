# frozen_string_literal: true

class AddBuiltinMetadataToSkillCatalogs < ActiveRecord::Migration[8.1]
  def change
    add_column :skill_catalogs, :source_type, :string, default: "manual", null: false
    add_column :skill_catalogs, :source_metadata, :jsonb, default: {}, null: false
  end
end
