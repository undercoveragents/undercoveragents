# frozen_string_literal: true

# == Schema Information
#
# Table name: test_cases
# Database name: primary
#
#  id                         :bigint           not null, primary key
#  category                   :string
#  complexity                 :string
#  disallow_child_chats       :boolean          default(FALSE), not null
#  expected_answer            :text
#  expected_child_builtin_key :string
#  expected_status            :string
#  expected_tool_names        :jsonb            not null
#  expected_variables         :jsonb            not null
#  fixture_key                :string
#  forbidden_keywords         :jsonb            not null
#  input_variables            :jsonb            not null
#  match_type                 :string           default("semantic"), not null
#  name                       :string
#  position                   :integer          default(0), not null
#  prompt                     :text
#  required_keywords          :jsonb            not null
#  scenario_key               :string
#  source_metadata            :jsonb            not null
#  source_type                :string           default("manual"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  test_suite_id              :bigint           not null
#
# Indexes
#
#  index_test_cases_on_scenario_key                (scenario_key)
#  index_test_cases_on_source_type                 (source_type)
#  index_test_cases_on_suite_and_scenario_key      (test_suite_id,scenario_key) UNIQUE WHERE (scenario_key IS NOT NULL)
#  index_test_cases_on_test_suite_id               (test_suite_id)
#  index_test_cases_on_test_suite_id_and_position  (test_suite_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (test_suite_id => test_suites.id)
#
class TestCase < ApplicationRecord
  EXPECTED_STATUSES = ["completed", "failed"].freeze
  SOURCE_TYPES = ["manual", "builtin"].freeze
  COMPLEXITIES = ["low", "medium", "high"].freeze
  enum :match_type, { exact: "exact", semantic: "semantic", partial: "partial" }, default: :semantic
  belongs_to :test_suite, inverse_of: :test_cases

  has_many :test_case_results, dependent: :destroy, inverse_of: :test_case

  scope :ordered, -> { order(:position) }
  scope :manual, -> { where(source_type: "manual") }
  scope :builtin, -> { where(source_type: "builtin") }
  validates :prompt, presence: true, length: { maximum: 5000 }, if: -> { test_suite&.agent? }
  validates :expected_answer, presence: true, length: { maximum: 10_000 }, if: -> { test_suite&.agent? }
  validates :name, presence: true, length: { maximum: 200 }, if: -> { test_suite&.mission? }
  validates :expected_status, inclusion: { in: EXPECTED_STATUSES }, if: -> { test_suite&.mission? }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :scenario_key, :category, :fixture_key, :expected_child_builtin_key, length: { maximum: 200 }
  validates :complexity, inclusion: { in: COMPLEXITIES }, allow_blank: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :json_columns_must_have_expected_shape

  before_validation :normalize_json_columns
  before_validation :normalize_strings

  def display_label
    name.presence || prompt&.truncate(80)
  end

  def builtin?
    source_type == "builtin"
  end

  def behavior_expectations?
    expected_child_builtin_key.present? || expected_tool_names.any? || disallow_child_chats? ||
      required_keywords.any? || forbidden_keywords.any?
  end

  def rendered_prompt(context = {})
    render_template(prompt, context)
  end

  def rendered_expected_answer(context = {})
    render_template(expected_answer, context)
  end

  def rendered_required_keywords(context = {})
    render_template_list(required_keywords, context)
  end

  def rendered_forbidden_keywords(context = {})
    render_template_list(forbidden_keywords, context)
  end

  private

  def render_template(value, context)
    template = value.to_s
    return template if template.blank? || context.blank?

    format(template, **context.to_h.deep_symbolize_keys)
  rescue KeyError
    template
  end

  def render_template_list(values, context)
    Array(values).map { |value| render_template(value, context) }.compact_blank
  end

  def normalize_json_columns
    self.source_metadata = {} unless source_metadata.is_a?(Hash)
    self.expected_tool_names = normalized_string_array(expected_tool_names)
    self.required_keywords = normalized_string_array(required_keywords)
    self.forbidden_keywords = normalized_string_array(forbidden_keywords)
  end

  def normalize_strings
    self.scenario_key = normalized_text(scenario_key).presence
    self.category = normalized_text(category).presence
    self.complexity = normalized_text(complexity).presence
    self.fixture_key = normalized_text(fixture_key).presence
    self.expected_child_builtin_key = normalized_text(expected_child_builtin_key).presence
  end

  def normalized_string_array(value)
    Array(value).filter_map { |item| normalized_text(item).presence }
  end

  def normalized_text(value)
    value.to_s.strip
  end

  def json_columns_must_have_expected_shape
    errors.add(:source_metadata, "must be a JSON object") unless source_metadata.is_a?(Hash)
    errors.add(:expected_tool_names, "must be an array") unless expected_tool_names.is_a?(Array)
    errors.add(:required_keywords, "must be an array") unless required_keywords.is_a?(Array)
    errors.add(:forbidden_keywords, "must be an array") unless forbidden_keywords.is_a?(Array)
  end
end
