# frozen_string_literal: true

class CreateSkillCatalogsAndSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_catalogs do |t|
      t.references :operation, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      t.timestamps
    end

    add_index :skill_catalogs, [:operation_id, :name], unique: true
    add_index :skill_catalogs, :slug, unique: true

    create_table :skills do |t|
      t.references :skill_catalog, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false
      t.text :instructions
      t.string :license
      t.string :compatibility
      t.string :allowed_tools
      t.string :source_type, null: false, default: "manual"
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :source_metadata, null: false, default: {}

      t.timestamps
    end

    add_index :skills, [:skill_catalog_id, :name], unique: true

    create_table :skill_resources do |t|
      t.references :skill, null: false, foreign_key: true
      t.string :relative_path, null: false
      t.string :resource_kind, null: false, default: "other"

      t.timestamps
    end

    add_index :skill_resources, [:skill_id, :relative_path], unique: true
  end
end
