# frozen_string_literal: true

class MakeOperationIdRequired < ActiveRecord::Migration[8.0]
  def up
    # Ensure Default operation exists before backfilling
    default_op = execute(<<~SQL).first
      SELECT id FROM operations WHERE name = 'Default' LIMIT 1
    SQL

    if default_op
      default_id = default_op["id"]
      %w[agents missions tools rag_flows].each do |table|
        execute "UPDATE #{table} SET operation_id = #{default_id} WHERE operation_id IS NULL"
      end
    end

    %w[agents missions tools rag_flows].each do |table|
      change_column_null table, :operation_id, false
    end
  end

  def down
    %w[agents missions tools rag_flows].each do |table|
      change_column_null table, :operation_id, true
    end
  end
end
