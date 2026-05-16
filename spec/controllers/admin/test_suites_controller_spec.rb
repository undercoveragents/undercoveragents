# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::TestSuitesController do
  describe "#ensure_builtin_test_suites!" do
    it "skips builtin sync when there is no current operation" do
      controller = described_class.new
      allow(controller).to receive(:current_operation).and_return(nil)
      allow(BuiltinTestSuites::Synchronizer).to receive(:ensure_present!)

      controller.send(:ensure_builtin_test_suites!)

      expect(BuiltinTestSuites::Synchronizer).not_to have_received(:ensure_present!)
    end

    it "syncs builtin suites for Headquarter" do
      tenant = create(:tenant)
      operation = instance_double(Operation, headquarter?: true)
      controller = described_class.new
      allow(controller).to receive_messages(current_operation: operation, current_tenant: tenant)
      allow(BuiltinTestSuites::Synchronizer).to receive(:ensure_present!)

      controller.send(:ensure_builtin_test_suites!)

      expect(BuiltinTestSuites::Synchronizer).to have_received(:ensure_present!).with(tenant:)
    end
  end
end
