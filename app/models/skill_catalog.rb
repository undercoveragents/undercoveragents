# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_catalogs
# Database name: primary
#
#  id              :bigint           not null, primary key
#  description     :text
#  name            :string           not null
#  slug            :string           not null
#  source_metadata :jsonb            not null
#  source_type     :string           default("manual"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operation_id    :bigint           not null
#
# Indexes
#
#  index_skill_catalogs_on_operation_id           (operation_id)
#  index_skill_catalogs_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_skill_catalogs_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class SkillCatalog < ApplicationRecord
  extend FriendlyId

  SOURCE_TYPES = ["manual", "builtin"].freeze

  attr_writer :skill_count, :assigned_agents_count, :total_resource_count, :imported_skills_count,
              :builtin_skills_count

  friendly_id :name, use: :slugged

  belongs_to :operation

  has_many :skills, -> { order(:name) }, dependent: :destroy, inverse_of: :skill_catalog

  scope :builtin, -> { where(source_type: "builtin") }
  scope :manual, -> { where(source_type: "manual") }
  scope :ordered, -> { order(:name) }
  validates :name, presence: true, uniqueness: { scope: :operation_id }, length: { maximum: 120 }
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validate :source_metadata_must_be_hash

  before_validation :normalize_source_metadata

  after_destroy_commit :detach_from_agents

  class << self
    def preload_index_metrics(skill_catalogs)
      return if skill_catalogs.empty?

      grouped_counts = load_grouped_counts(skill_catalogs)

      skill_catalogs.each do |skill_catalog|
        skill_catalog.skill_count = grouped_counts[:skills].fetch(skill_catalog.id, 0)
        skill_catalog.imported_skills_count = grouped_counts[:imported_skills].fetch(skill_catalog.id, 0)
        skill_catalog.builtin_skills_count = grouped_counts[:builtin_skills].fetch(skill_catalog.id, 0)
        skill_catalog.total_resource_count = grouped_counts[:resources].fetch(skill_catalog.id, 0)
        skill_catalog.assigned_agents_count = grouped_counts[:assigned_agents].fetch(skill_catalog.id, 0)
      end
    end

    private

    def load_grouped_counts(skill_catalogs)
      catalog_ids = skill_catalogs.map(&:id)

      {
        skills: Skill.where(skill_catalog_id: catalog_ids).group(:skill_catalog_id).count,
        imported_skills: Skill.imported.where(skill_catalog_id: catalog_ids).group(:skill_catalog_id).count,
        builtin_skills: Skill.builtin.where(skill_catalog_id: catalog_ids).group(:skill_catalog_id).count,
        resources: grouped_resource_counts(catalog_ids),
        assigned_agents: grouped_assigned_agent_counts(skill_catalogs, catalog_ids),
      }
    end

    def grouped_resource_counts(catalog_ids)
      SkillResource.joins(:skill)
                   .where(skills: { skill_catalog_id: catalog_ids })
                   .group(Skill.arel_table[:skill_catalog_id])
                   .count
    end

    def grouped_assigned_agent_counts(skill_catalogs, catalog_ids)
      counts = Hash.new(0)
      operation_ids = skill_catalogs.map(&:operation_id).uniq
      catalog_lookup = catalog_ids.index_with(true)

      Agent.where(operation_id: operation_ids).select(:id, :configuration).find_each do |agent|
        agent.skill_catalog_ids.each do |catalog_id|
          counts[catalog_id] += 1 if catalog_lookup[catalog_id]
        end
      end

      counts
    end
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  def manual?
    source_type == "manual"
  end

  def builtin?
    source_type == "builtin"
  end

  def builtin_key
    source_metadata["builtin_key"].presence
  end

  def assigned_agents
    Agent.where(operation_id:)
         .where("configuration->'skill_catalog_ids' @> ?", [id].to_json)
         .ordered
  end

  def skill_count
    count = @skill_count
    return count.to_i unless count.nil?

    skills.size
  end

  def assigned_agents_count
    count = @assigned_agents_count
    return count.to_i unless count.nil?

    assigned_agents.count
  end

  def total_resource_count
    count = @total_resource_count
    return count.to_i unless count.nil?

    SkillResource.joins(:skill).where(skills: { skill_catalog_id: id }).count
  end

  def imported_skills_count
    count = @imported_skills_count
    return count.to_i unless count.nil?

    skills.imported.count
  end

  def builtin_skills_count
    count = @builtin_skills_count
    return count.to_i unless count.nil?

    skills.builtin.count
  end

  private

  def normalize_source_metadata
    self.source_metadata = {} unless source_metadata.is_a?(Hash)
  end

  def source_metadata_must_be_hash
    errors.add(:source_metadata, "must be a JSON object") unless source_metadata.is_a?(Hash)
  end

  def detach_from_agents
    Agent.where("configuration->'skill_catalog_ids' @> ?", [id].to_json).find_each do |agent|
      next unless agent.skill_catalog_ids.include?(id)

      agent.skill_catalog_ids = agent.skill_catalog_ids - [id]
      agent.save!(validate: false)
    end
  end
end
