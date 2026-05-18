# frozen_string_literal: true

# == Schema Information
#
# Table name: operations
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  icon        :string           default("fa-solid fa-briefcase")
#  name        :string           not null
#  slug        :string           not null
#  system      :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  tenant_id   :bigint           not null
#
# Indexes
#
#  index_operations_on_slug                (slug) UNIQUE
#  index_operations_on_system              (system)
#  index_operations_on_tenant_id           (tenant_id)
#  index_operations_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
class Operation < ApplicationRecord
  extend FriendlyId

  attr_writer :agent_count, :mission_count, :tool_count, :skill_catalog_count, :rag_flow_count

  friendly_id :name, use: :slugged

  HEADQUARTER_NAME = "Headquarter"
  DEFAULT_NAME = "Default"
  belongs_to :tenant
  has_many :channels, dependent: :restrict_with_error
  has_many :agents, dependent: :restrict_with_error
  has_many :missions, dependent: :restrict_with_error
  has_many :tools, dependent: :restrict_with_error
  has_many :skill_catalogs, dependent: :restrict_with_error
  has_many :rag_flows, dependent: :restrict_with_error

  scope :ordered, -> { order(:name) }
  scope :headquarter_first, -> { order(Arel.sql("CASE WHEN name = 'Headquarter' THEN 0 ELSE 1 END"), :name) }
  scope :user_managed, -> { where(system: false) }
  scope :for_tenant, ->(tenant) { where(tenant:) }
  validates :name, presence: true, uniqueness: { scope: :tenant_id, case_sensitive: false }, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }

  # ── System Operations ──

  class << self
    def preload_counts(operations)
      return if operations.empty?

      grouped_counts = load_grouped_counts(operations.map(&:id))

      operations.each do |operation|
        assign_counts(operation, grouped_counts)
      end
    end

    private

    def load_grouped_counts(operation_ids)
      {
        agents: Agent.where(operation_id: operation_ids).group(:operation_id).count,
        missions: Mission.where(operation_id: operation_ids).group(:operation_id).count,
        tools: Tool.where(operation_id: operation_ids).group(:operation_id).count,
        skill_catalogs: SkillCatalog.where(operation_id: operation_ids).group(:operation_id).count,
        rag_flows: RagFlow.where(operation_id: operation_ids).group(:operation_id).count,
      }
    end

    def assign_counts(operation, grouped_counts)
      operation.agent_count = grouped_counts[:agents].fetch(operation.id, 0)
      operation.mission_count = grouped_counts[:missions].fetch(operation.id, 0)
      operation.tool_count = grouped_counts[:tools].fetch(operation.id, 0)
      operation.skill_catalog_count = grouped_counts[:skill_catalogs].fetch(operation.id, 0)
      operation.rag_flow_count = grouped_counts[:rag_flows].fetch(operation.id, 0)
    end
  end

  def self.headquarter(tenant = Current.tenant || Tenant.default_tenant)
    return if tenant.blank?

    where(tenant:).find_by(name: HEADQUARTER_NAME)
  end

  def self.default_operation(tenant = Current.tenant || Tenant.default_tenant)
    return if tenant.blank?

    where(tenant:).find_by(name: DEFAULT_NAME)
  end

  # ── Caching ──

  def self.current_operation_id(session)
    session[:current_operation_id]
  end

  def self.set_current_operation(session, operation)
    session[:current_operation_id] = operation&.id
  end

  # ── Helpers ──

  def headquarter?
    name == HEADQUARTER_NAME && system?
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  def agent_count
    preloaded_count(@agent_count, agents)
  end

  def mission_count
    preloaded_count(@mission_count, missions)
  end

  def tool_count
    preloaded_count(@tool_count, tools)
  end

  def skill_catalog_count
    preloaded_count(@skill_catalog_count, skill_catalogs)
  end

  def rag_flow_count
    preloaded_count(@rag_flow_count, rag_flows)
  end

  def destroyable?
    !system? &&
      agent_count.zero? &&
      mission_count.zero? &&
      tool_count.zero? &&
      skill_catalog_count.zero? &&
      rag_flow_count.zero?
  end

  private

  def preloaded_count(count, association)
    return count.to_i unless count.nil?

    association.size
  end
end
