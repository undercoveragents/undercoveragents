# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SkillsController do
  describe "#ensure_builtin_skill_catalogs!" do
    it "syncs builtin skill catalogs for the current tenant" do
      tenant = create(:tenant)
      allow(controller).to receive(:current_tenant).and_return(tenant)
      allow(BuiltinSkills::Synchronizer).to receive(:ensure_present!)

      controller.send(:ensure_builtin_skill_catalogs!)

      expect(BuiltinSkills::Synchronizer).to have_received(:ensure_present!).with(tenant:)
    end
  end

  describe "#headquarter_operation?" do
    it "returns nil when there is no current operation" do
      allow(controller).to receive(:current_operation).and_return(nil)

      expect(controller.send(:headquarter_operation?)).to be_nil
    end
  end

  describe "#warning_summary" do
    it "returns nil when there are no warnings" do
      expect(controller.send(:warning_summary, [])).to be_nil
    end

    it "formats a singular warning summary" do
      expect(controller.send(:warning_summary, ["One warning"])).to eq("1 warning.")
    end

    it "formats a plural warning summary" do
      expect(controller.send(:warning_summary, ["One warning", "Two warnings"])).to eq("2 warnings.")
    end
  end

  describe "#parsed_metadata_json" do
    it "treats blank metadata JSON as an empty object" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(skill: { metadata_json: "" }))

      expect(controller.send(:parsed_metadata_json)).to eq({})
    end
  end

  describe "#save_skill_with_resources" do
    let(:skill_catalog) { create(:skill_catalog) }

    it "adds a metadata error when invalid JSON is encountered before any other error is present" do
      skill = skill_catalog.skills.new(name: "renewal-playbook", description: "Helpful guidance")
      params = ActionController::Parameters.new(skill: { metadata_json: "{invalid" })
      allow(controller).to receive(:params).and_return(params)

      expect(controller.send(:save_skill_with_resources, skill)).to be(false)
      expect(skill.errors[:metadata]).to include("must contain valid JSON")
    end

    it "returns false when persistence raises a record invalid error" do
      skill = skill_catalog.skills.new(name: "renewal-playbook", description: "Helpful guidance")
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(skill: { metadata_json: "{}" }))
      allow(skill).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(skill))

      expect(controller.send(:save_skill_with_resources, skill)).to be(false)
    end
  end
end
