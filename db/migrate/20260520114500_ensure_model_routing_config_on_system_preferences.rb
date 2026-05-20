# frozen_string_literal: true

class EnsureModelRoutingConfigOnSystemPreferences < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:system_preferences, :model_routing_config)

    add_column :system_preferences, :model_routing_config, :jsonb, default: {}, null: false
  end
end
