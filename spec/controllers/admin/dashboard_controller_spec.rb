# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DashboardController do
  describe "#reset_operation_selection_on_direct_entry" do
    it "returns early when no current tenant is available" do
      allow(controller).to receive(:current_tenant).and_return(nil)
      allow(request).to receive(:referer).and_return(nil)

      expect(controller.send(:reset_operation_selection_on_direct_entry)).to be_nil
    end
  end
end
