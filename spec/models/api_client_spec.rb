# frozen_string_literal: true

# == Schema Information
#
# Table name: api_clients
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_scope :string           default("all"), not null
#  description  :text
#  enabled      :boolean          default(TRUE), not null
#  last_used_at :datetime
#  name         :string           not null
#  token_digest :string           not null
#  token_prefix :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  tenant_id    :bigint           not null
#
# Indexes
#
#  index_api_clients_on_enabled             (enabled)
#  index_api_clients_on_tenant_id           (tenant_id)
#  index_api_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#  index_api_clients_on_token_prefix        (token_prefix) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe ApiClient do
  subject(:api_client) { build(:api_client) }

  describe "associations" do
    it { is_expected.to have_many(:api_client_missions).dependent(:destroy) }
    it { is_expected.to have_many(:missions).through(:api_client_missions) }
    it { is_expected.to have_many(:mission_runs).dependent(:nullify) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:tenant_id).case_insensitive }
    it { is_expected.to validate_presence_of(:token_prefix) }
    it { is_expected.to validate_uniqueness_of(:token_prefix) }
    it { is_expected.to validate_presence_of(:token_digest) }
  end

  describe "enums" do
    it do
      expect(api_client).to define_enum_for(:access_scope)
        .with_values(all: "all", scoped: "scoped")
        .backed_by_column_of_type(:string)
        .with_prefix(:scope)
    end
  end

  describe "scopes" do
    describe ".enabled" do
      it "returns only enabled clients" do
        enabled = create(:api_client, enabled: true)
        create(:api_client, :disabled)

        expect(described_class.enabled).to eq([enabled])
      end
    end

    describe ".ordered" do
      it "orders by name" do
        beta = create(:api_client, name: "Beta")
        alpha = create(:api_client, name: "Alpha")

        expect(described_class.ordered).to eq([alpha, beta])
      end
    end
  end

  describe ".generate_token" do
    it "returns a hash with raw_token, prefix, and digest" do
      token_data = described_class.generate_token

      expect(token_data).to include(:raw_token, :prefix, :digest)
      expect(token_data[:raw_token]).to start_with("ua_")
      expect(token_data[:prefix]).to start_with("ua_")
      expect(token_data[:prefix].length).to eq(11) # "ua_" + 8 hex chars
      expect(token_data[:digest]).to eq(Digest::SHA256.hexdigest(token_data[:raw_token]))
    end
  end

  describe ".authenticate" do
    let(:token_data) { described_class.generate_token }
    let!(:client) do
      create(:api_client, token_prefix: token_data[:prefix], token_digest: token_data[:digest])
    end

    it "returns the client for a valid token" do
      result = described_class.authenticate(token_data[:raw_token])
      expect(result).to eq(client)
    end

    it "updates last_used_at on successful authentication" do
      described_class.authenticate(token_data[:raw_token])
      expect(client.reload.last_used_at).to be_within(2.seconds).of(Time.current)
    end

    it "returns nil for an invalid token" do
      expect(described_class.authenticate("ua_invalid_token_here")).to be_nil
    end

    it "returns nil for a blank token" do
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end

    it "returns nil for a token without the correct prefix" do
      expect(described_class.authenticate("invalid_prefix_token")).to be_nil
    end

    it "returns nil for a disabled client" do
      client.update!(enabled: false)
      expect(described_class.authenticate(token_data[:raw_token])).to be_nil
    end

    it "returns nil when the provided tenant does not match the client tenant" do
      expect(described_class.authenticate(token_data[:raw_token], tenant: create(:tenant))).to be_nil
    end

    it "returns nil when token prefix matches but digest does not" do
      # Use a token with the correct prefix but different body
      tampered = "#{client.token_prefix}#{"a" * 56}"
      expect(described_class.authenticate(tampered)).to be_nil
    end
  end

  describe "#can_access_mission?" do
    let(:mission) { create(:mission) }

    context "when access_scope is all" do
      let(:client) { create(:api_client, access_scope: "all") }

      it "returns true for any mission" do
        expect(client.can_access_mission?(mission)).to be true
      end
    end

    context "when access_scope is scoped" do
      let(:client) { create(:api_client, :scoped) }

      it "returns true for an assigned mission" do
        create(:api_client_mission, api_client: client, mission:)
        expect(client.can_access_mission?(mission)).to be true
      end

      it "returns false for an unassigned mission" do
        expect(client.can_access_mission?(mission)).to be false
      end
    end

    it "returns false for a mission from another tenant" do
      client = create(:api_client)
      other_mission = create(:mission, operation: create(:operation, tenant: create(:tenant)))

      expect(client.can_access_mission?(other_mission)).to be(false)
    end
  end

  describe "#masked_token" do
    it "masks the token with asterisks" do
      client = create(:api_client)
      masked = client.masked_token

      expect(masked).to start_with(client.token_prefix)
      expect(masked).to include("*" * 24)
      expect(masked).to end_with(client.token_digest.last(8))
    end
  end

  describe "#regenerate_token!" do
    it "generates a new token and updates the digest" do
      client = create(:api_client)
      old_prefix = client.token_prefix
      old_digest = client.token_digest

      new_raw_token = client.regenerate_token!

      expect(new_raw_token).to start_with("ua_")
      expect(client.reload.token_prefix).not_to eq(old_prefix)
      expect(client.token_digest).not_to eq(old_digest)
      expect(client.token_digest).to eq(Digest::SHA256.hexdigest(new_raw_token))
    end
  end

  describe "tenant mission scoping" do
    it "rejects scoped missions from another tenant" do
      tenant = create(:tenant)
      other_tenant = create(:tenant)
      mission = create(:mission, operation: create(:operation, tenant: other_tenant))
      api_client = create(:api_client, :scoped, tenant:)
      create(:api_client_mission, api_client:, mission:)

      expect(api_client).not_to be_valid
      expect(api_client.errors[:mission_ids]).to include("must belong to the same tenant")
    end

    it "accepts scoped missions from the same tenant" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      mission = create(:mission, operation:)
      api_client = create(:api_client, :scoped, tenant:)
      create(:api_client_mission, api_client:, mission:)

      expect(api_client).to be_valid
    end
  end

  describe "#accessible_missions_scope" do
    it "returns all tenant missions for all-scope clients" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      mission = create(:mission, operation:)
      create(:mission, operation: create(:operation, tenant: create(:tenant)))
      api_client = create(:api_client, tenant:, access_scope: "all")

      expect(api_client.accessible_missions_scope).to contain_exactly(mission)
    end

    it "returns only assigned tenant missions for scoped clients" do
      tenant = create(:tenant)
      operation = create(:operation, tenant:)
      assigned = create(:mission, operation:)
      unassigned = create(:mission, operation:)
      api_client = create(:api_client, :scoped, tenant:)
      create(:api_client_mission, api_client:, mission: assigned)

      expect(api_client.accessible_missions_scope).to contain_exactly(assigned)
      expect(api_client.accessible_missions_scope).not_to include(unassigned)
    end
  end
end
