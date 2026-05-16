# frozen_string_literal: true

# Wrapper model for rag step modules.
# Each RagFlow has up to 4 steps (one per stage). Each step stores its
# module_type key (e.g. "fixed_size_chunker") and a JSONB configuration hash
# with the module-specific attributes. The actual behavior is provided by a
# configurator object resolved via RagStepPlugin.
#
# == Schema Information
#
# Table name: rag_steps
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  module_type   :string           not null
#  stage         :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_flow_id   :bigint           not null
#
# Indexes
#
#  idx_rag_steps_flow_stage        (rag_flow_id,stage) UNIQUE
#  index_rag_steps_on_rag_flow_id  (rag_flow_id)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
class RagStep < ApplicationRecord
  STAGES = ["source", "chunking", "embedding", "storage"].freeze
  STAGE_ORDER_SQL = "CASE stage " \
                    "WHEN 'source' THEN 1 WHEN 'chunking' THEN 2 " \
                    "WHEN 'embedding' THEN 3 WHEN 'storage' THEN 4 END"

  belongs_to :rag_flow, inverse_of: :rag_steps

  delegate :execute, :each_batch, :validate_configuration!, to: :configurator

  scope :ordered, -> { order(Arel.sql(STAGE_ORDER_SQL)) }

  validates :stage, uniqueness: { scope: :rag_flow_id }
  validates :stage, presence: true, inclusion: { in: STAGES }
  validates :module_type, presence: true

  # Amoeba — JSONB columns copy naturally, no custom steppable cloning needed
  amoeba do
    enable
  end

  # Returns an ActiveModel configurator instance for the module_type,
  # hydrated with the JSONB configuration attributes.
  def configurator
    @configurator = nil if module_type_changed? || configuration_changed?
    @configurator ||= build_configurator
  end

  def type_label
    configurator.label
  rescue RuntimeError => e
    return "Unknown module" if e.message.start_with?("Unknown module type:")

    raise
  end

  def summary
    configurator.summary
  rescue RuntimeError => e
    return module_type.to_s.humanize if e.message.start_with?("Unknown module type:")

    raise
  end

  private

  def build_configurator
    klass = RagStepPlugin.resolve(module_type)
    raise "Unknown module type: #{module_type}" unless klass

    configurator = klass.new(configuration.symbolize_keys)
    configurator._rag_step_record = self if configurator.respond_to?(:_rag_step_record=)
    configurator
  end
end
