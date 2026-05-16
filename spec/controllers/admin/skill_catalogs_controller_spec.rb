# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SkillCatalogsController do
  describe "#import_target_mode" do
    it "falls back to new when the requested mode is invalid" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(target_mode: "invalid"))

      expect(controller.send(:import_target_mode)).to eq("new")
    end

    it "returns an allowed requested mode unchanged" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(target_mode: "existing"))

      expect(controller.send(:import_target_mode)).to eq("existing")
    end
  end

  describe "#resolve_import_target" do
    it "builds a new operation-scoped catalog when the target mode is new" do
      operation = create(:operation)
      allow(controller).to receive(:current_operation).and_return(operation)

      skill_catalog = controller.send(:resolve_import_target, "new")

      expect(skill_catalog).to be_a(SkillCatalog)
      expect(skill_catalog).to be_new_record
      expect(skill_catalog.operation).to eq(operation)
    end
  end

  describe "#render_missing_import_upload" do
    it "does not build a new catalog when targeting an existing catalog" do
      existing_catalog = create(:skill_catalog)
      allow(controller).to receive(:t).and_return("Upload required")
      allow(controller).to receive(:render)
      controller.instance_variable_set(:@skill_catalog, existing_catalog)

      controller.send(:render_missing_import_upload, "existing")

      expect(controller.instance_variable_get(:@skill_catalog)).to eq(existing_catalog)
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
      expect(controller.send(:warning_summary, ["One warning", "Two warning"])).to eq("2 warnings.")
    end
  end

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
end
