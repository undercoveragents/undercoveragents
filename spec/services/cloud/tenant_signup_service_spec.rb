# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cloud::TenantSignupService do
  describe "#call" do
    it "generates a workspace name from the admin email" do
      result = described_class.new(
        admin_email: "owner@orbit.test",
        password: "Validpass1!",
        password_confirmation: "Validpass1!",
      ).call

      expect(result).to be_success
      expect(result.tenant.name).to eq("owner workspace")
    end

    it "adds a number when the generated workspace name already exists" do
      create(:tenant, name: "owner workspace")

      result = described_class.new(
        admin_email: "owner@orbit.test",
        password: "Validpass1!",
        password_confirmation: "Validpass1!",
      ).call

      expect(result).to be_success
      expect(result.tenant.name).to eq("owner workspace 2")
    end

    it "adds an error when an OAuth signup is missing its uid" do
      result = described_class.new(
        admin_email: "owner@orbit.test",
        oauth_identity: { provider: "google", uid: nil },
      ).call

      expect(result).not_to be_success
      expect(result.errors).to include("Uid can't be blank")
    end

    it "returns a failure result when persistence raises after validation" do
      allow_any_instance_of(User).to receive(:save!) do |instance| # rubocop:disable RSpec/AnyInstance
        instance.errors.add(:base, "forced failure")
        error = ActiveRecord::RecordInvalid.new(instance)
        raise error
      end

      result = described_class.new(
        admin_email: "owner@orbit.test",
        password: "Validpass1!",
        password_confirmation: "Validpass1!",
      ).call

      expect(result).not_to be_success
      expect(result.errors).to include("forced failure")
    end
  end
end
