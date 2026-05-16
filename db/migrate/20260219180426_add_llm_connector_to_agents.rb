class AddLlmConnectorToAgents < ActiveRecord::Migration[8.1]
  def change
    add_reference :agents, :llm_connector, foreign_key: { to_table: :connectors }, null: true, index: true
  end
end
