# frozen_string_literal: true

# == Schema Information
#
# Table name: missions
# Database name: primary
#
#  id                :bigint           not null, primary key
#  description       :text
#  flow_data         :jsonb            not null
#  flow_redo_history :jsonb            not null
#  flow_undo_history :jsonb            not null
#  name              :string           not null
#  slug              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operation_id      :bigint           not null
#
# Indexes
#
#  index_missions_on_name          (name)
#  index_missions_on_operation_id  (operation_id)
#  index_missions_on_slug          (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class Mission < ApplicationRecord
  include Missions::FlowHistory
  extend FriendlyId

  FILE_FIELD_TYPES = ["file", "file_array"].freeze

  friendly_id :name, use: :slugged

  belongs_to :operation
  has_many :mission_runs, dependent: :destroy
  has_many :test_suites, dependent: :destroy
  has_many :api_client_missions, dependent: :destroy
  has_many :api_clients, through: :api_client_missions

  scope :ordered, -> { order(:name) }
  validates :name, presence: true, length: { maximum: 255 }

  # ── Input field accessors (single source of truth) ──

  def input_fields
    input_node = (flow_data&.dig("nodes") || []).find { |n| n["type"] == "input" }
    return [] unless input_node

    normalize_raw_fields(input_node.dig("data", "fields"))
  end

  def input_field_names
    input_fields.filter_map { |f| f["variable_name"].presence }
  end

  def input_field_definitions
    input_fields.filter_map do |field|
      variable_name = field["variable_name"].presence
      next unless variable_name

      {
        variable_name:,
        field_type: field["field_type"] || "string",
        required: field["required"].present?,
        label: field["label"].presence || variable_name,
      }
    end
  end

  def output_field_names
    output_node = (flow_data&.dig("nodes") || []).find { |n| n["type"] == "output" }
    return [] unless output_node

    (output_node.dig("data", "selected_variables") || []).filter_map(&:presence)
  end

  def output_field_definitions
    output_field_names.map { |variable_name| { variable_name: } }
  end

  def global_variable_keys
    (flow_data&.dig("global_variables") || []).filter_map { |variable| variable["key"].presence }
  end

  def file_field_names
    input_fields
      .select { |f| FILE_FIELD_TYPES.include?(f["field_type"]) }
      .filter_map { |f| f["variable_name"].presence }
  end

  def file_fields?
    file_field_names.any?
  end

  def filter_trigger_data(data)
    names = input_field_names
    return data if names.empty?

    allowed_names = names + Missions::LlmNodeRuntimeConfig::RUNTIME_CONFIG_KEYS
    data.is_a?(Hash) ? data.slice(*allowed_names) : data
  end

  def validate_required_inputs(data)
    input_fields
      .select { |f| f["required"].present? && f.dig("config", "default_value").blank? }
      .filter_map { |f| f["variable_name"].presence }
      .select { |name| data[name].nil? }
  end

  def flow_data=(value)
    super(Missions::FlowDataSanitizer.parse_and_sanitize(value))
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  private

  def normalize_raw_fields(raw)
    raw = JSON.parse(raw) if raw.is_a?(String)
    raw.is_a?(Array) ? raw : []
  rescue JSON::ParserError
    []
  end
end
