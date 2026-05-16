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
require "rails_helper"

RSpec.describe ChannelTarget do
  subject(:channel_target) { build(:channel_target) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:target) }
    it { is_expected.to have_many(:channel_conversations).dependent(:nullify) }
    it { is_expected.to have_many(:chats).dependent(:nullify) }
    it { is_expected.to have_many(:mission_runs).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_length_of(:slug).is_at_most(120) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
    it { is_expected.to validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }

    it "derives name and slug from the target" do
      target = build(:channel_target, name: nil, slug: nil)

      target.valid?

      expect(target.name).to eq(target.target.name)
      expect(target.slug).to eq(target.target.name.parameterize)
    end

    it "rejects target kinds not supported by the channel type" do
      mission = create(:mission)
      channel = create(:channel, :client, tenant: mission.operation.tenant)
      target = build(:channel_target, channel:, target: mission)

      expect(target).not_to be_valid
      expect(target.errors[:target_type]).to include("is not allowed for this channel type")
    end

    it "rejects targets from a different tenant" do
      target = build(:channel_target, target: create(:agent))

      target.channel.tenant = create(:tenant)

      expect(target).not_to be_valid
      expect(target.errors[:target]).to include("must belong to the same tenant as the channel")
    end

    it "normalizes invalid configuration payloads" do
      target = build(:channel_target)
      target.configuration = "invalid"

      target.valid?

      expect(target.configuration).to eq({})
    end

    it "falls back to a parameterized name when the target slug is blank" do
      target = build(:channel_target, name: "Manual Name", slug: nil)

      allow(target.target).to receive(:slug).and_return(nil)

      target.valid?

      expect(target.slug).to eq("manual-name")
    end

    it "returns nil for unknown target tenant ids" do
      target = build(:channel_target)

      allow(target).to receive(:target).and_return(Object.new)

      expect(target.send(:target_tenant_id)).to be_nil
    end

    it "returns nil for derived names when the target has no name reader" do
      target = build(:channel_target)

      allow(target).to receive(:target).and_return(Object.new)

      expect(target.send(:derived_target_name)).to be_nil
    end

    it "falls back to the parameterized name when the target has no slug reader" do
      target = build(:channel_target, name: "Manual Name")

      allow(target).to receive(:target).and_return(Object.new)

      expect(target.send(:derived_target_slug)).to eq("manual-name")
    end
  end
end
