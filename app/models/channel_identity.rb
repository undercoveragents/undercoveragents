# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_identities
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  external_username     :string
#  link_token_digest     :string
#  linked_at             :datetime
#  metadata              :jsonb            not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  channel_id            :bigint           not null
#  external_user_id      :string           not null
#  external_workspace_id :string
#  user_id               :bigint
#
# Indexes
#
#  index_channel_identities_on_channel_id                       (channel_id)
#  index_channel_identities_on_channel_id_and_external_user_id  (channel_id,external_user_id) UNIQUE
#  index_channel_identities_on_external_workspace_id            (external_workspace_id)
#  index_channel_identities_on_link_token_digest                (link_token_digest) UNIQUE
#  index_channel_identities_on_user_id                          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#  fk_rails_...  (user_id => users.id)
#
class ChannelIdentity < ApplicationRecord
  belongs_to :channel
  belongs_to :user, optional: true

  has_many :channel_conversations, dependent: :nullify

  scope :linked, -> { where.not(linked_at: nil) }
  validates :external_user_id, presence: true, uniqueness: { scope: :channel_id }
  validates :external_username, length: { maximum: 255 }
  validates :external_workspace_id, length: { maximum: 255 }
  validates :link_token_digest, uniqueness: true, allow_blank: true
  validate :user_must_belong_to_channel_tenant

  attribute :metadata, :jsonb, default: -> { {} }

  before_validation :ensure_metadata

  private

  def ensure_metadata
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def user_must_belong_to_channel_tenant
    return if user.blank? || channel.blank?
    return if user.tenant_id == channel.tenant_id

    errors.add(:user, "must belong to the same tenant as the channel")
  end
end
