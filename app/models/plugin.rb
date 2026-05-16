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
class Plugin < ApplicationRecord
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :ordered, -> { order(:identifier) }
  validates :identifier, presence: true, uniqueness: true
  validates :enabled, inclusion: { in: [true, false] }

  # Returns the in-memory Definition from the plugin registry
  def definition
    UndercoverAgents::PluginSystem.registry.find(identifier)
  end

  # Convenience accessors from metadata JSONB
  def plugin_name
    metadata&.dig("name") || identifier.titleize
  end

  def plugin_version
    metadata&.dig("version") || "0.0.0"
  end

  def plugin_author
    metadata&.dig("author") || "Unknown"
  end

  def plugin_description
    metadata&.dig("description") || ""
  end

  def plugin_icon
    metadata&.dig("icon") || "fa-solid fa-puzzle-piece"
  end

  def plugin_category
    metadata&.dig("category") || "general"
  end

  def plugin_stage
    metadata&.dig("stage")
  end
end
