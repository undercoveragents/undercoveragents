# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_resources
# Database name: primary
#
#  id            :bigint           not null, primary key
#  relative_path :string           not null
#  resource_kind :string           default("other"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  skill_id      :bigint           not null
#
# Indexes
#
#  index_skill_resources_on_skill_id                    (skill_id)
#  index_skill_resources_on_skill_id_and_relative_path  (skill_id,relative_path) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (skill_id => skills.id)
#
class SkillResource < ApplicationRecord
  RESOURCE_KINDS = ["scripts", "references", "assets", "other"].freeze

  has_one_attached :file
  belongs_to :skill, inverse_of: :skill_resources

  scope :ordered, -> { order(:relative_path) }
  validates :relative_path, presence: true, uniqueness: { scope: :skill_id }, length: { maximum: 255 }
  validates :resource_kind, inclusion: { in: RESOURCE_KINDS }
  validate :relative_path_must_be_safe
  validate :file_must_be_attached

  before_validation :normalize_relative_path
  before_validation :infer_resource_kind

  def filename
    File.basename(relative_path)
  end

  private

  def normalize_relative_path
    self.relative_path = relative_path.to_s.tr("\\", "/").squeeze("/").delete_prefix("/")
  end

  def infer_resource_kind
    first_segment = relative_path.to_s.split("/").first.to_s
    self.resource_kind = RESOURCE_KINDS.include?(first_segment) ? first_segment : "other"
  end

  def relative_path_must_be_safe
    return if relative_path.blank?

    path = Pathname.new(relative_path)
    return unless path.absolute? || relative_path.split("/").include?("..")

    errors.add(:relative_path, "must stay inside the skill directory")
  end

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end
end
