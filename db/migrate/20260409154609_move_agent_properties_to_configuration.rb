# frozen_string_literal: true

class MoveAgentPropertiesToConfiguration < ActiveRecord::Migration[8.1]
  def up
    # 1. Add configuration JSONB column to agents
    add_column :agents, :configuration, :jsonb, null: false, default: {}

    # 2. Migrate existing agent data into configuration
    execute <<~SQL
      UPDATE agents SET configuration = jsonb_build_object(
        'description', COALESCE(description, ''),
        'instructions', COALESCE(instructions, ''),
        'model_id', COALESCE(model_id, ''),
        'temperature', COALESCE(temperature, 0.7),
        'llm_connector_id', llm_connector_id,
        'enabled', COALESCE(enabled, true),
        'tool_ids', COALESCE((
          SELECT jsonb_agg(at.tool_id ORDER BY at.position)
          FROM agent_tools at
          WHERE at.agent_id = agents.id
        ), '[]'::jsonb),
        'subagent_ids', COALESCE((
          SELECT jsonb_agg(asub.subagent_id ORDER BY asub.position)
          FROM agent_subagents asub
          WHERE asub.agent_id = agents.id
        ), '[]'::jsonb),
        'capabilities', COALESCE((
          SELECT jsonb_object_agg(
            c.capability_type,
            c.configuration || jsonb_build_object('enabled', c.enabled)
          )
          FROM capabilities c
          WHERE c.agent_id = agents.id
        ), '{}'::jsonb)
      )
    SQL

    # 3. Remove old columns from agents (keep name, slug)
    remove_foreign_key :agents, :connectors, column: :llm_connector_id, if_exists: true
    remove_column :agents, :description
    remove_column :agents, :instructions
    remove_column :agents, :model_id
    remove_column :agents, :temperature
    remove_column :agents, :llm_connector_id
    remove_column :agents, :enabled

    # 4. Drop join tables & capabilities
    drop_table :agent_tools
    drop_table :agent_subagents
    drop_table :capabilities
  end

  def down
    # Recreate the removed columns
    add_column :agents, :description, :text
    add_column :agents, :instructions, :text
    add_column :agents, :model_id, :string
    add_column :agents, :temperature, :float, default: 0.7, null: false
    add_reference :agents, :llm_connector, foreign_key: { to_table: :connectors }
    add_column :agents, :enabled, :boolean, default: true, null: false
    add_index :agents, :enabled

    # Recreate agent_tools
    create_table :agent_tools do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :tool, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :agent_tools, [:agent_id, :tool_id], unique: true

    # Recreate agent_subagents
    create_table :agent_subagents do |t|
      t.references :agent, null: false, foreign_key: true
      t.bigint :subagent_id, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :agent_subagents, [:agent_id, :subagent_id], unique: true
    add_index :agent_subagents, :subagent_id
    add_foreign_key :agent_subagents, :agents, column: :subagent_id

    # Recreate capabilities
    create_table :capabilities do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :capability_type, null: false
      t.jsonb :configuration, null: false, default: {}
      t.boolean :enabled, default: true, null: false
      t.timestamps
    end
    add_index :capabilities, [:agent_id, :capability_type], unique: true
    add_index :capabilities, :capability_type
    add_index :capabilities, :enabled

    # Migrate data back from configuration JSONB
    execute <<~SQL
      UPDATE agents SET
        description = configuration->>'description',
        instructions = configuration->>'instructions',
        model_id = configuration->>'model_id',
        temperature = (configuration->>'temperature')::float,
        llm_connector_id = (configuration->>'llm_connector_id')::bigint,
        enabled = (configuration->>'enabled')::boolean
    SQL

    remove_column :agents, :configuration
  end
end
