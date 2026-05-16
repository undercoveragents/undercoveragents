# frozen_string_literal: true

class ChangeEnabledDefaultToTrueForCapabilitiesRagFlowsAndTools < ActiveRecord::Migration[8.1]
  def change
    change_column_default :capabilities, :enabled, from: false, to: true
    change_column_default :rag_flows, :enabled, from: false, to: true
    change_column_default :tools, :enabled, from: false, to: true
  end
end
