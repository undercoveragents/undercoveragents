# frozen_string_literal: true

class AddOperationIdToResources < ActiveRecord::Migration[8.1]
  def change
    add_reference :agents, :operation, null: true, foreign_key: true
    add_reference :missions, :operation, null: true, foreign_key: true
    add_reference :tools, :operation, null: true, foreign_key: true
    add_reference :rag_flows, :operation, null: true, foreign_key: true
  end
end
