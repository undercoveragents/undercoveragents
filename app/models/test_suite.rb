# frozen_string_literal: true

# == Schema Information
#
# Table name: test_suites
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  description                 :text
#  evaluation_temperature      :float            default(0.7), not null
#  name                        :string           not null
#  slug                        :string
#  source_metadata             :jsonb            not null
#  source_type                 :string           default("manual"), not null
#  status                      :string           default("active"), not null
#  suite_type                  :string           default("agent"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  agent_id                    :bigint
#  evaluation_llm_connector_id :bigint
#  evaluation_model_id         :string
#  mission_id                  :bigint
#
# Indexes
#
#  index_test_suites_on_agent_id                     (agent_id)
#  index_test_suites_on_builtin_key                  (((source_metadata ->> 'builtin_key'::text))) WHERE ((source_type)::text = 'builtin'::text)
#  index_test_suites_on_evaluation_llm_connector_id  (evaluation_llm_connector_id)
#  index_test_suites_on_mission_id                   (mission_id)
#  index_test_suites_on_name                         (name)
#  index_test_suites_on_slug                         (slug) UNIQUE
#  index_test_suites_on_source_type                  (source_type)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (evaluation_llm_connector_id => connectors.id)
#  fk_rails_...  (mission_id => missions.id)
#
class TestSuite < ApplicationRecord
  extend FriendlyId

  attr_writer :test_case_count

  friendly_id :name, use: :slugged

  TEMPERATURE_RANGE = (0.0..2.0)
  DEFAULT_TEMPERATURE = 0.7
  SOURCE_TYPES = ["manual", "builtin"].freeze

  enum :status, { active: "active", archived: "archived" }, default: :active
  enum :suite_type, { agent: "agent", mission: "mission" }, default: :agent
  belongs_to :agent, optional: true
  belongs_to :mission, optional: true
  belongs_to :evaluation_llm_connector, class_name: "Connector", optional: true

  has_many :test_cases, -> { order(:position) }, dependent: :destroy, inverse_of: :test_suite
  has_many :test_suite_runs, -> { order(created_at: :desc) }, dependent: :destroy, inverse_of: :test_suite

  scope :manual, -> { where(source_type: "manual") }
  scope :builtin, -> { where(source_type: "builtin") }
  scope :ordered, -> { order(:name) }
  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :evaluation_model_id, length: { maximum: 200 }
  validates :evaluation_temperature, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :agent_id, presence: true, if: :agent?
  validates :mission_id, presence: true, if: :mission?
  validate :source_metadata_must_be_hash
  validate :evaluation_connector_must_be_llm_provider

  before_validation :normalize_source_metadata

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  def latest_run
    test_suite_runs.first
  end

  def test_case_count
    count = @test_case_count
    return count.to_i unless count.nil?

    test_cases.size
  end

  def can_run?
    active? && test_case_count.positive?
  end

  def target
    agent? ? agent : mission
  end

  def operation
    target&.operation
  end

  def tenant
    operation&.tenant
  end

  def builtin?
    source_type == "builtin"
  end

  def builtin_key
    source_metadata["builtin_key"].presence
  end

  def target_name
    target&.name
  end

  def target_icon
    agent? ? "fa-solid fa-user-secret" : "fa-solid fa-diagram-project"
  end

  def suite_icon
    agent? ? "fa-solid fa-vial-circle-check" : "fa-solid fa-flask-vial"
  end

  def input_fields
    return [] unless mission?
    return [] unless mission.flow_data

    nodes = mission.flow_data["nodes"] || []
    input_node = nodes.find { |n| n["type"] == "input" }
    input_node&.dig("data", "fields") || []
  end

  def resolve_evaluation_context
    connector = evaluation_llm_connector || agent&.resolved_llm_connector
    connector&.build_context
  end

  def resolved_evaluation_model_id
    evaluation_model_id.presence || agent&.resolved_model_id
  end

  private

  def normalize_source_metadata
    self.source_metadata = {} unless source_metadata.is_a?(Hash)
  end

  def source_metadata_must_be_hash
    errors.add(:source_metadata, "must be a JSON object") unless source_metadata.is_a?(Hash)
  end

  def evaluation_connector_must_be_llm_provider
    return if evaluation_llm_connector_id.blank?
    return if evaluation_llm_connector&.connector_type == "llm_provider"

    errors.add(:evaluation_llm_connector_id, "must be an LLM Provider connector")
  end
end
