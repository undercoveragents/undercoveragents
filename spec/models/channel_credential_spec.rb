# frozen_string_literal: true

# == Schema Information
#
# Table name: channel_credentials
# Database name: primary
#
#  id              :bigint           not null, primary key
#  credential_type :string           default("bearer_token"), not null
#  enabled         :boolean          default(TRUE), not null
#  last_used_at    :datetime
#  metadata        :jsonb            not null
#  name            :string           not null
#  token_digest    :string           not null
#  token_prefix    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  channel_id      :bigint           not null
#
# Indexes
#
#  index_channel_credentials_on_channel_id           (channel_id)
#  index_channel_credentials_on_channel_id_and_name  (channel_id,name) UNIQUE
#  index_channel_credentials_on_enabled              (enabled)
#  index_channel_credentials_on_token_prefix         (token_prefix) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (channel_id => channels.id)
#
require "rails_helper"

RSpec.describe ChannelCredential do
  subject(:credential) { build(:channel_credential) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }

    it "validates channel-scoped unique names" do
      existing = create(:channel_credential, name: "Public API")
      duplicate = build(:channel_credential, channel: existing.channel, name: "public api")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "validates unique token prefixes" do
      existing = create(:channel_credential)
      duplicate = build(:channel_credential, token_prefix: existing.token_prefix)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token_prefix]).to include("has already been taken")
    end

    it "requires explicitly blank token fields" do
      credential.token_prefix = ""
      credential.token_digest = ""

      expect(credential).not_to be_valid
      expect(credential.errors[:token_prefix]).to include("can't be blank")
      expect(credential.errors[:token_digest]).to include("can't be blank")
    end

    it "normalizes invalid metadata payloads" do
      credential.metadata = "invalid"

      credential.valid?

      expect(credential.metadata).to eq({})
    end

    it "does not overwrite existing token fields during validation" do
      credential = build(:channel_credential, token_prefix: "ch_existing", token_digest: "digest")

      credential.valid?

      expect(credential.token_prefix).to eq("ch_existing")
      expect(credential.token_digest).to eq("digest")
    end
  end

  describe ".generate_token" do
    it "returns a raw token, prefix, and digest" do
      token_data = described_class.generate_token

      expect(token_data[:raw_token]).to start_with("ch_")
      expect(token_data[:prefix].length).to eq(11)
      expect(token_data[:digest]).to eq(Digest::SHA256.hexdigest(token_data[:raw_token]))
    end
  end

  describe ".authenticate" do
    let(:token_data) { described_class.generate_token }
    let!(:credential) do
      create(:channel_credential, token_prefix: token_data[:prefix], token_digest: token_data[:digest])
    end

    it "returns the credential for a valid token" do
      expect(described_class.authenticate(token_data[:raw_token])).to eq(credential)
    end

    it "updates last_used_at on successful authentication" do
      described_class.authenticate(token_data[:raw_token])

      expect(credential.reload.last_used_at).to be_within(2.seconds).of(Time.current)
    end

    it "returns nil for invalid tokens" do
      expect(described_class.authenticate("ch_invalid")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("ua_wrong_prefix")).to be_nil
    end

    it "returns nil when scoped to another channel or tenant" do
      expect(described_class.authenticate(token_data[:raw_token], channel: create(:channel, :api))).to be_nil
      expect(described_class.authenticate(token_data[:raw_token], tenant: create(:tenant))).to be_nil
    end

    it "returns nil when the token prefix matches but the digest does not" do
      tampered = "#{credential.token_prefix}#{"a" * 56}"

      expect(described_class.authenticate(tampered)).to be_nil
    end
  end

  describe "#regenerate_token!" do
    it "updates the stored digest and returns the new raw token" do
      credential = create(:channel_credential)
      old_digest = credential.token_digest

      raw_token = credential.regenerate_token!

      expect(raw_token).to start_with("ch_")
      expect(credential.reload.token_digest).not_to eq(old_digest)
      expect(credential.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
    end
  end
end
