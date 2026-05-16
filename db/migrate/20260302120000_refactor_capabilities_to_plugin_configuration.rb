# frozen_string_literal: true

class RefactorCapabilitiesToPluginConfiguration < ActiveRecord::Migration[8.1]
  def up
    add_column :capabilities, :capability_type, :string
    add_column :capabilities, :configuration, :jsonb, null: false, default: {}

    execute <<~SQL
      UPDATE capabilities AS c
      SET capability_type = 'chat_title_generator',
          configuration = jsonb_build_object(
            'max_length', tg.max_length,
            'max_turns', tg.max_turns,
            'llm_config_source', tg.llm_config_source,
            'llm_connector_id', tg.llm_connector_id,
            'model_id', tg.model_id,
            'temperature', tg.temperature
          )
      FROM capabilities_title_generators AS tg
      WHERE c.capabilitable_type = 'Capabilities::TitleGenerator'
        AND c.capabilitable_id = tg.id
    SQL

    execute <<~SQL
      UPDATE capabilities AS c
      SET capability_type = 'telegram',
          configuration = jsonb_build_object(
            'telegram_connector_id', t.telegram_connector_id,
            'welcome_message', t.welcome_message,
            'max_history_messages', t.max_history_messages
          )
      FROM capabilities_telegrams AS t
      WHERE c.capabilitable_type = 'Capabilities::Telegram'
        AND c.capabilitable_id = t.id
    SQL

    remove_index :capabilities, name: "index_capabilities_on_capabilitable_type_and_capabilitable_id"
    remove_index :capabilities, name: "index_capabilities_on_agent_id_and_capabilitable_type"

    remove_column :capabilities, :capabilitable_type, :string
    remove_column :capabilities, :capabilitable_id, :bigint

    change_column_null :capabilities, :capability_type, false

    add_index :capabilities, [:agent_id, :capability_type], unique: true
    add_index :capabilities, :capability_type

    drop_table :capabilities_title_generators
    drop_table :capabilities_telegrams
  end

  def down
    create_table :capabilities_title_generators do |t|
      t.integer :max_length, null: false, default: 30
      t.integer :max_turns, null: false, default: 3
      t.string :llm_config_source, null: false, default: "inherit"
      t.references :llm_connector, foreign_key: { to_table: :connectors }
      t.string :model_id
      t.float :temperature, default: 0.7
      t.timestamps
    end

    create_table :capabilities_telegrams do |t|
      t.bigint :telegram_connector_id, null: false
      t.text :welcome_message,
             default: "Welcome! I'm your AI assistant. Send me a message to start chatting, or use /help to see available commands."
      t.integer :max_history_messages, default: 50, null: false
      t.timestamps
    end

    add_foreign_key :capabilities_telegrams, :connectors, column: :telegram_connector_id
    add_index :capabilities_telegrams, :telegram_connector_id

    add_column :capabilities, :capabilitable_type, :string
    add_column :capabilities, :capabilitable_id, :bigint

    execute <<~SQL
      WITH inserted AS (
        INSERT INTO capabilities_title_generators (
          max_length, max_turns, llm_config_source, llm_connector_id, model_id, temperature, created_at, updated_at
        )
        SELECT
          COALESCE((configuration ->> 'max_length')::integer, 30),
          COALESCE((configuration ->> 'max_turns')::integer, 3),
          COALESCE(configuration ->> 'llm_config_source', 'inherit'),
          (configuration ->> 'llm_connector_id')::bigint,
          configuration ->> 'model_id',
          COALESCE((configuration ->> 'temperature')::float, 0.7),
          NOW(),
          NOW()
        FROM capabilities
        WHERE capability_type = 'chat_title_generator'
        RETURNING id
      )
      SELECT 1
    SQL

    execute <<~SQL
      WITH title_caps AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS row_num
        FROM capabilities
        WHERE capability_type = 'chat_title_generator'
      ),
      title_rows AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS row_num
        FROM capabilities_title_generators
      )
      UPDATE capabilities AS c
      SET capabilitable_type = 'Capabilities::TitleGenerator',
          capabilitable_id = tr.id
      FROM title_caps tc
      JOIN title_rows tr ON tc.row_num = tr.row_num
      WHERE c.id = tc.id
    SQL

    execute <<~SQL
      WITH inserted AS (
        INSERT INTO capabilities_telegrams (
          telegram_connector_id, welcome_message, max_history_messages, created_at, updated_at
        )
        SELECT
          (configuration ->> 'telegram_connector_id')::bigint,
          configuration ->> 'welcome_message',
          COALESCE((configuration ->> 'max_history_messages')::integer, 50),
          NOW(),
          NOW()
        FROM capabilities
        WHERE capability_type = 'telegram'
        RETURNING id
      )
      SELECT 1
    SQL

    execute <<~SQL
      WITH telegram_caps AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS row_num
        FROM capabilities
        WHERE capability_type = 'telegram'
      ),
      telegram_rows AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS row_num
        FROM capabilities_telegrams
      )
      UPDATE capabilities AS c
      SET capabilitable_type = 'Capabilities::Telegram',
          capabilitable_id = tr.id
      FROM telegram_caps tc
      JOIN telegram_rows tr ON tc.row_num = tr.row_num
      WHERE c.id = tc.id
    SQL

    change_column_null :capabilities, :capabilitable_type, false
    change_column_null :capabilities, :capabilitable_id, false

    remove_index :capabilities, :capability_type
    remove_index :capabilities, column: [:agent_id, :capability_type]

    remove_column :capabilities, :capability_type, :string
    remove_column :capabilities, :configuration, :jsonb

    add_index :capabilities, [:capabilitable_type, :capabilitable_id], unique: true
    add_index :capabilities, [:agent_id, :capabilitable_type], unique: true
  end
end
