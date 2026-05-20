# frozen_string_literal: true

class AddModelRoutingConfigToSystemPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :system_preferences, :model_routing_config, :jsonb, default: {}, null: false
  end
end
