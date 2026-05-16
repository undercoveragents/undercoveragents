# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sidebar" do
  describe "PATCH /admin/sidebar" do
    it "saves collapsed state to session" do
      patch admin_sidebar_path, params: { collapsed: true }, as: :json

      expect(response).to have_http_status(:no_content)
    end

    it "persists collapsed state across requests" do
      patch admin_sidebar_path, params: { collapsed: true }, as: :json

      get admin_root_path

      expect(response.body).to include('data-admin-sidebar-collapsed-value="true"')
    end

    it "persists expanded state across requests" do
      patch admin_sidebar_path, params: { collapsed: false }, as: :json

      get admin_root_path

      expect(response.body).to include('data-admin-sidebar-collapsed-value="false"')
    end
  end
end
