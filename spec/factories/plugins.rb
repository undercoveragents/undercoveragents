# frozen_string_literal: true

# == Schema Information
#
# Table name: plugins
# Database name: primary
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  identifier :string           not null
#  metadata   :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_plugins_on_identifier  (identifier) UNIQUE
#
FactoryBot.define do
  factory :plugin do
    sequence(:identifier) { |n| "test_plugin_#{n}" }
    enabled { true }
    metadata { { "name" => "Test Plugin", "version" => "1.0.0", "author" => "Test" } }

    trait :disabled do
      enabled { false }
    end
  end
end
