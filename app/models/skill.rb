# frozen_string_literal: true

# == Schema Information
#
# Table name: skills
# Database name: primary
#
#  id               :bigint           not null, primary key
#  allowed_tools    :string
#  compatibility    :string
#  description      :text             not null
#  instructions     :text
#  license          :string
#  metadata         :jsonb            not null
#  name             :string           not null
#  source_metadata  :jsonb            not null
#  source_type      :string           default("manual"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  skill_catalog_id :bigint           not null
#
# Indexes
#
#  index_skills_on_skill_catalog_id           (skill_catalog_id)
#  index_skills_on_skill_catalog_id_and_name  (skill_catalog_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_catalog_id => skill_catalogs.id)
#
class Skill < ApplicationRecord
  SOURCE_TYPES = ["manual", "imported", "builtin"].freeze

  belongs_to :skill_catalog, inverse_of: :skills

  has_many :skill_resources, -> { order(:relative_path) }, dependent: :destroy, inverse_of: :skill

  scope :ordered, -> { order(:name) }
  scope :manual, -> { where(source_type: "manual") }
  scope :imported, -> { where(source_type: "imported") }
  scope :builtin, -> { where(source_type: "builtin") }
  validates :name, presence: true, uniqueness: { scope: :skill_catalog_id }, length: { maximum: 120 }
  validates :description, presence: true, length: { maximum: 2000 }
  validates :compatibility, length: { maximum: 500 }, allow_blank: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validate :json_columns_must_be_hashes

  before_validation :normalize_json_columns
  before_validation :normalize_strings

  def manual?
    source_type == "manual"
  end

  def imported?
    source_type == "imported"
  end

  def builtin?
    source_type == "builtin"
  end

  def builtin_key
    source_metadata["builtin_key"].presence
  end

  def skill_markdown
    Skills::MarkdownBuilder.new(self).build
  end

  def skill_identifier
    builtin_catalog_key = skill_catalog.builtin_key
    return "#{builtin_catalog_key}/#{builtin_key}" if builtin_catalog_key.present? && builtin_key.present?

    "#{skill_catalog.slug}/#{id}"
  end

  def spec_warnings
    Skills::SpecificationValidator.new(
      name:,
      description:,
      compatibility:,
      directory_name: source_metadata["directory_name"],
    ).warnings
  end

  private

  def normalize_json_columns
    self.metadata = {} unless metadata.is_a?(Hash)
    self.source_metadata = {} unless source_metadata.is_a?(Hash)
  end

  def normalize_strings
    self.name = normalized_text(name)
    self.description = normalized_text(description)
    normalize_optional_texts(:license, :compatibility, :allowed_tools)
    self.instructions = instructions.to_s.rstrip
  end

  def normalize_optional_texts(*attributes)
    attributes.each do |attribute|
      self[attribute] = normalized_text(self[attribute]).presence
    end
  end

  def normalized_text(value)
    value.to_s.strip
  end

  def json_columns_must_be_hashes
    errors.add(:metadata, "must be a JSON object") unless metadata.is_a?(Hash)
    errors.add(:source_metadata, "must be a JSON object") unless source_metadata.is_a?(Hash)
  end
end
