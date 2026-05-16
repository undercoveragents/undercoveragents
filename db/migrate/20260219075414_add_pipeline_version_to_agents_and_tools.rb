# frozen_string_literal: true

class AddPipelineVersionToAgentsAndTools < ActiveRecord::Migration[8.1]
  def change
    add_reference :agents, :pipeline_version, null: true, foreign_key: true, index: true
    add_reference :tools, :pipeline_version, null: true, foreign_key: true, index: true
  end
end
