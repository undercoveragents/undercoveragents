# frozen_string_literal: true

class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_channels
    create_channel_targets
    create_channel_identities
    create_channel_credentials
    create_channel_conversations
    add_channel_links_to_runtime_records
  end

  private

  def create_channels
    create_table :channels do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :connector, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :channel_type, null: false
      t.jsonb :configuration, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.boolean :default, null: false, default: false

      t.timestamps
    end

    add_index :channels, :slug, unique: true
    add_index :channels, [:tenant_id, :name], unique: true
    add_index :channels, :channel_type
    add_index :channels, :enabled
    add_index :channels, :default
  end

  def create_channel_targets
    create_table :channel_targets do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :default, null: false, default: false
      t.integer :position, null: false, default: 0
      t.jsonb :configuration, null: false, default: {}

      t.timestamps
    end

    add_index :channel_targets, [:channel_id, :target_type, :target_id], unique: true
    add_index :channel_targets, [:channel_id, :slug], unique: true
    add_index :channel_targets, [:target_type, :target_id]
    add_index :channel_targets, :default
  end

  def create_channel_identities
    create_table :channel_identities do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :external_user_id, null: false
      t.string :external_username
      t.string :external_workspace_id
      t.string :link_token_digest
      t.datetime :linked_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :channel_identities, [:channel_id, :external_user_id], unique: true
    add_index :channel_identities, :external_workspace_id
    add_index :channel_identities, :link_token_digest, unique: true
  end

  def create_channel_credentials
    create_table :channel_credentials do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :credential_type, null: false, default: "bearer_token"
      t.string :name, null: false
      t.string :token_prefix, null: false
      t.string :token_digest, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_used_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :channel_credentials, [:channel_id, :name], unique: true
    add_index :channel_credentials, :token_prefix, unique: true
    add_index :channel_credentials, :enabled
  end

  def create_channel_conversations
    create_table :channel_conversations do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :channel_target, foreign_key: true
      t.references :channel_identity, foreign_key: true
      t.references :chat, foreign_key: true
      t.references :mission_run, foreign_key: true
      t.string :external_conversation_id, null: false
      t.string :external_thread_id, null: false, default: ""
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :channel_conversations,
              [:channel_id, :external_conversation_id, :external_thread_id],
              unique: true,
              name: "index_channel_conversations_on_external_ids"
  end

  def add_channel_links_to_runtime_records
    add_reference :chats, :channel, foreign_key: true
    add_reference :chats, :channel_target, foreign_key: true
    add_reference :chats, :channel_conversation, foreign_key: true
    add_reference :mission_runs, :channel, foreign_key: true
    add_reference :mission_runs, :channel_target, foreign_key: true
    add_reference :mission_runs, :channel_conversation, foreign_key: true
  end
end
