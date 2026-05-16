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
require "rails_helper"

RSpec.describe ChannelIdentity do
  describe "validations" do
    it "normalizes metadata to a hash" do
      identity = build(:channel_identity, metadata: "invalid")

      identity.valid?

      expect(identity.metadata).to eq({})
    end

    it "rejects users from a different tenant" do
      channel = create(:channel, tenant: create(:tenant))
      identity = build(:channel_identity, channel:, user: create(:user, tenant: create(:tenant)))

      expect(identity).not_to be_valid
      expect(identity.errors[:user]).to include("must belong to the same tenant as the channel")
    end

    it "is valid without a linked user" do
      expect(build(:channel_identity, user: nil)).to be_valid
    end

    it "accepts users from the same tenant" do
      tenant = create(:tenant)
      create(:operation, tenant:)
      user = create(:user, tenant:)
      channel = create(:channel, tenant:)
      identity = build(:channel_identity, channel:, user:)

      expect(identity).to be_valid
    end
  end

  describe ".linked" do
    it "returns only linked identities" do
      linked = create(:channel_identity, linked_at: Time.current)
      create(:channel_identity, linked_at: nil)

      expect(described_class.linked).to contain_exactly(linked)
    end
  end
end
