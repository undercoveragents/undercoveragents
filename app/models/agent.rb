# frozen_string_literal: true

# == Schema Information
#
# Table name: agents
# Database name: primary
#
#  id            :bigint           not null, primary key
#  agent_type    :string
#  builtin       :boolean          default(FALSE), not null
#  configuration :jsonb            not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_agents_on_agent_type                  (agent_type)
#  index_agents_on_operation_and_name          (operation_id,name) UNIQUE
#  index_agents_on_operation_id                (operation_id)
#  index_agents_on_slug                        (slug) UNIQUE
#  index_agents_on_type_and_operation_builtin  (agent_type,operation_id) UNIQUE WHERE (builtin = true)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class Agent < ApplicationRecord
  include AgentConfiguration
  include AgentRuntime
  include HasCapabilities
  include HasSkillCatalogs
  extend FriendlyId

  UNSET = Object.new

  friendly_id :name, use: :slugged

  belongs_to :operation
  has_many :chats, dependent: :destroy
  has_many :test_suites, dependent: :destroy
  delegate :tenant, to: :operation, allow_nil: true

  scope :enabled, -> { where("(configuration->>'enabled')::boolean = true") }
  scope :disabled, -> { where("(configuration->>'enabled')::boolean IS DISTINCT FROM true") }
  scope :builtin, -> { where("(configuration->>'builtin')::boolean = true") }
  scope :user_created, -> { where("(configuration->>'builtin')::boolean IS DISTINCT FROM true") }
  scope :selectable, -> { where("(configuration->>'selectable')::boolean IS DISTINCT FROM false") }
  scope :ordered, -> { order(:name) }

  validate :validate_subagent_references
  validate :validate_skill_catalog_references
  validates :name, presence: true, uniqueness: { scope: :operation_id }, length: { maximum: 100 }

  def self.find_builtin_by_key(key, tenant: Current.tenant || Tenant.default_tenant)
    scope = builtin.where("configuration ->> 'builtin_key' = ?", key.to_s)
    return scope.first if tenant.blank?

    scope.joins(:operation).find_by(operations: { tenant_id: tenant.id })
  end

  # ── FriendlyId ──

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  def resolved_model_id
    return SystemPreference.current(tenant:).model_id if llm_config_source == "system_preference"

    model_id
  end

  def resolved_llm_connector
    return SystemPreference.current(tenant:).llm_connector if llm_config_source == "system_preference"

    llm_connector
  end

  # ── Amoeba ──

  amoeba do
    enable
    prepend name: "Copy of "

    override lambda { |original, copy|
      copy.configuration = original.configuration.deep_dup
    }
  end

  private

  def validate_subagent_references
    return if subagent_ids.empty?

    errors.add(:subagent_ids, "cannot include the agent itself") if subagent_ids.include?(id)
    return unless persisted?

    subagent_ids.each do |sub_id|
      next unless creates_cycle_with?(sub_id)

      errors.add(:subagent_ids, "would create a cyclic reference")
      break
    end
  end

  def validate_skill_catalog_references
    return if skill_catalog_ids.empty?

    existing_catalogs = SkillCatalog.where(id: skill_catalog_ids)
    missing_ids = skill_catalog_ids - existing_catalogs.pluck(:id)
    errors.add(:skill_catalog_ids, "contain unknown skill catalogs") if missing_ids.any?

    cross_operation = existing_catalogs.where.not(operation_id:)
    return if cross_operation.none?

    errors.add(:skill_catalog_ids, "must belong to the same operation as the agent")
  end

  def creates_cycle_with?(sub_id)
    visited = Set.new
    queue = [sub_id]

    while queue.any?
      current_id = queue.shift
      next if visited.include?(current_id)

      visited << current_id

      child_ids = Agent.where(id: current_id).pick(:configuration)&.dig("subagent_ids") || []
      return true if child_ids.include?(id)

      queue.concat(child_ids.map(&:to_i))
    end

    false
  end
end
