# frozen_string_literal: true

class MoveClientContentToConfiguration < ActiveRecord::Migration[8.1]
  class MigrationClient < ApplicationRecord
    self.table_name = "clients"
  end

  def up
    add_column :clients, :configuration, :jsonb, default: {}, null: false

    MigrationClient.reset_column_information

    say_with_time "Migrating client content into configuration" do
      MigrationClient.find_each do |client|
        client.update_columns(configuration: migrated_configuration_for(client))
      end
    end

    remove_column :clients, :title, :text
    remove_column :clients, :welcome_message, :text
    remove_column :clients, :footer, :text
  end

  def down
    add_column :clients, :title, :text
    add_column :clients, :welcome_message, :text
    add_column :clients, :footer, :text

    MigrationClient.reset_column_information

    say_with_time "Restoring client content columns from configuration" do
      MigrationClient.find_each do |client|
        content = client[:configuration].is_a?(Hash) ? client[:configuration].deep_stringify_keys.fetch("content", {}) : {}

        client.update_columns(
          title: content["title"],
          welcome_message: content["welcome_message"],
          footer: content["footer"],
        )
      end
    end

    remove_column :clients, :configuration, :jsonb
  end

  private

  def migrated_configuration_for(client)
    content = {
      "title" => client[:title],
      "welcome_message" => client[:welcome_message],
      "footer" => client[:footer],
    }.compact

    { "content" => content }
  end
end
