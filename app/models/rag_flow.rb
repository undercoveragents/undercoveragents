# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_flows
# Database name: primary
#
#  id           :bigint           not null, primary key
#  enabled      :boolean          default(TRUE), not null
#  name         :string           not null
#  slug         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  operation_id :bigint           not null
#
# Indexes
#
#  index_rag_flows_on_operation_id           (operation_id)
#  index_rag_flows_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_rag_flows_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class RagFlow < ApplicationRecord
  extend FriendlyId

  friendly_id :name, use: :slugged

  # The 4 fixed stages in execution order
  STAGES = [
    { key: :source, label: "Document Rag", icon: "fa-solid fa-database", position: 1 },
    { key: :chunking, label: "Chunking", icon: "fa-solid fa-scissors", position: 2 },
    { key: :embedding, label: "Embedding", icon: "fa-solid fa-vector-square", position: 3 },
    { key: :storage, label: "Index Storage", icon: "fa-solid fa-hard-drive", position: 4 },
  ].freeze
  belongs_to :operation

  # Steps use delegated_type — one RagStep per stage, each pointing to a steppable module
  has_many :rag_steps, dependent: :destroy, inverse_of: :rag_flow

  # Convenience accessors for each stage
  has_one :source_step, -> { where(stage: "source") },
          class_name: "RagStep", inverse_of: :rag_flow, dependent: :destroy
  has_one :chunking_step, -> { where(stage: "chunking") },
          class_name: "RagStep", inverse_of: :rag_flow, dependent: :destroy
  has_one :embedding_step, -> { where(stage: "embedding") },
          class_name: "RagStep", inverse_of: :rag_flow, dependent: :destroy
  has_one :storage_step, -> { where(stage: "storage") },
          class_name: "RagStep", inverse_of: :rag_flow, dependent: :destroy

  has_many :rag_runs, dependent: :destroy, inverse_of: :rag_flow

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:name) }
  validates :name, presence: true, uniqueness: { scope: :operation_id, case_sensitive: false }, length: { maximum: 100 }

  # Configure amoeba for deep cloning
  amoeba do
    enable
    include_association :rag_steps
    exclude_association :rag_runs
    prepend name: "Copy of "
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  def last_run
    rag_runs.order(created_at: :desc).first
  end

  def runnable?
    enabled?
  end

  # Returns the RagStep record for a given stage key, or nil
  def step_for(stage_key)
    rag_steps.find_by(stage: stage_key.to_s)
  end

  # Returns the configurator for a given stage, or nil
  def module_for(stage_key)
    step_for(stage_key)&.configurator
  end

  # Returns stage config hash for a given key
  def self.stage_config(key)
    STAGES.find { |s| s[:key] == key.to_sym }
  end

  # Whether a stage has been configured (has a module selected)
  def stage_configured?(key)
    step_for(key).present?
  end

  # Whether all 4 stages have been configured (required to run)
  def fully_configured?
    STAGES.all? { |s| stage_configured?(s[:key]) }
  end

  # Returns all stages with their step records (may include nils if not yet created)
  def ordered_stages
    STAGES.map { |s| [s, step_for(s[:key])] }
  end
end
