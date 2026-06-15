# frozen_string_literal: true

class AddCostAnalysisFoundation < ActiveRecord::Migration[8.1]
  def change
    add_cost_columns_to_messages
    add_attribution_to_chats
    create_cost_limits
  end

  private

  def add_cost_columns_to_messages
    change_table :messages, bulk: true do |t|
      t.decimal :input_cost_usd, precision: 18, scale: 8
      t.decimal :cached_input_cost_usd, precision: 18, scale: 8
      t.decimal :cache_creation_cost_usd, precision: 18, scale: 8
      t.decimal :output_cost_usd, precision: 18, scale: 8
      t.decimal :cost_usd, precision: 18, scale: 8
      t.string :cost_currency, null: false, default: "USD"
      t.jsonb :cost_pricing_snapshot, null: false, default: {}
      t.datetime :cost_calculated_at
    end

    add_index :messages, :cost_usd
    add_index :messages, :cost_calculated_at
  end

  def add_attribution_to_chats
    add_reference :chats, :tenant, foreign_key: true
    add_reference :chats, :operation, foreign_key: true
    add_index :chats, [:tenant_id, :operation_id]
  end

  def create_cost_limits
    create_table :cost_limits do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :operation, foreign_key: true
      t.string :name, null: false
      t.string :target_type, null: false
      t.bigint :target_id
      t.string :target_key
      t.string :period, null: false
      t.decimal :amount_usd, null: false, precision: 18, scale: 6
      t.integer :warning_threshold_percent, null: false, default: 80
      t.string :enforcement_mode, null: false, default: "warn_only"
      t.boolean :enabled, null: false, default: true
      t.text :description

      t.timestamps
    end

    add_index :cost_limits, [:tenant_id, :enabled]
    add_index :cost_limits, [:tenant_id, :target_type, :target_id, :target_key], name: "idx_cost_limits_on_target"
    add_index :cost_limits, [:tenant_id, :operation_id]
  end
end
