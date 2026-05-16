# frozen_string_literal: true

class RenameMemoryBlocksValueToDefaultValue < ActiveRecord::Migration[8.1]
  def change
    rename_column :memory_blocks, :value, :default_value
  end
end
