# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_targets
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  slug          :string           not null
#  target_type   :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  channel_id    :bigint           not null
#  target_id     :bigint           not null
#
# Indexes
#
#  idx_on_channel_id_target_type_target_id_7f034238bd  (channel_id,target_type,target_id) UNIQUE
#  index_channel_targets_on_channel_id                 (channel_id)
#  index_channel_targets_on_channel_id_and_slug        (channel_id,slug) UNIQUE
#  index_channel_targets_on_default                    (default)
#  index_channel_targets_on_target_type_and_target_id  (target_type,target_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#
class ChannelTarget < ApplicationRecord
  TARGET_TYPES = ["Agent", "Mission"].freeze

  belongs_to :channel
  belongs_to :target, polymorphic: true

  has_many :channel_conversations, dependent: :nullify
  has_many :chats, dependent: :nullify
  has_many :mission_runs, dependent: :nullify

  scope :ordered, -> { order(:position, :name) }
  scope :defaults, -> { where(default: true) }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: [:channel_id, :target_type] }
  validates :slug, presence: true, uniqueness: { scope: :channel_id }, length: { maximum: 120 }
  validates :name, presence: true, length: { maximum: 120 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :target_kind_allowed_for_channel
  validate :target_must_belong_to_channel_tenant

  attribute :configuration, :jsonb, default: -> { {} }

  before_validation :ensure_configuration
  before_validation :derive_name_and_slug

  def target_kind
    target_type.to_s.underscore
  end

  private

  def ensure_configuration
    self.configuration = {} unless configuration.is_a?(Hash)
  end

  def derive_name_and_slug
    return unless target

    self.name = derived_target_name if name.blank?
    self.slug = derived_target_slug if slug.blank?
  end

  def derived_target_name
    target.name if target.respond_to?(:name)
  end

  def derived_target_slug
    target_slug = target.slug if target.respond_to?(:slug)
    target_slug.presence || name.to_s.parameterize.presence
  end

  def target_kind_allowed_for_channel
    return if channel.blank? || target_type.blank?
    return if channel.allowed_target_kinds.include?(target_kind)

    errors.add(:target_type, "is not allowed for this channel type")
  end

  def target_must_belong_to_channel_tenant
    return if channel.blank? || target.blank?
    return if target_tenant_id == channel.tenant_id

    errors.add(:target, "must belong to the same tenant as the channel")
  end

  def target_tenant_id
    case target
    when Agent, Mission
      target.operation.tenant_id
    end
  end
end
