# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::BaseController do
  controller(described_class) do
    skip_before_action :require_authentication

    def index
      head :ok
    end
  end

  before do
    routes.draw { get "admin" => "anonymous#index" }
  end

  describe "#reset_operation_to_default_on_admin_entry" do
    it "handles a missing current tenant" do
      allow(controller).to receive_messages(
        current_user: build(:user, :admin),
        current_tenant: nil,
        admin_root_path: "/admin",
      )
      allow(request).to receive_messages(get?: true, path: "/admin", referer: nil)

      expect do
        controller.send(:reset_operation_to_default_on_admin_entry)
      end.not_to(change { session[:current_operation_id] })
    end
  end
end
