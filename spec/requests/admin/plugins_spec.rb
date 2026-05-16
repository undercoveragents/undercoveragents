# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Plugins" do
  describe "GET /admin/plugins" do
    it "lists all plugins" do
      get admin_plugins_path
      expect(response).to have_http_status(:ok)
    end

    context "when non-admin" do
      before do
        non_admin = create(:user, role: "user")
        post sessions_path, params: { email: non_admin.email, password: "Password123!" }
      end

      it "redirects with error" do
        get admin_plugins_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when unauthenticated", :unauthenticated do
      it "redirects to login" do
        get admin_plugins_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "PATCH /admin/plugins/:id/toggle" do
    let(:plugin_identifier) { "fixed_size_chunker" }

    before do
      # Ensure the plugin record exists
      Plugin.find_or_create_by!(identifier: plugin_identifier) do |p|
        p.enabled = true
        p.metadata = { "name" => "Fixed Size Chunker" }
      end
    end

    it "toggles the plugin enabled state" do
      plugin = Plugin.find_by!(identifier: plugin_identifier)
      original_state = plugin.enabled

      patch toggle_admin_plugin_path(plugin_identifier)

      expect(plugin.reload.enabled).to eq(!original_state)
    end

    it "redirects to plugins index with a notice" do
      patch toggle_admin_plugin_path(plugin_identifier)
      expect(response).to redirect_to(admin_plugins_path)
      expect(flash[:notice]).to be_present
    end

    it "shows enabled notice when toggling from disabled to enabled" do
      plugin = Plugin.find_by!(identifier: plugin_identifier)
      plugin.update!(enabled: false)
      patch toggle_admin_plugin_path(plugin_identifier)
      expect(flash[:notice]).to include("enabled")
    end

    it "returns 404 for unknown plugin identifier" do
      patch toggle_admin_plugin_path("nonexistent_plugin_xyz")
      expect(response).to have_http_status(:not_found)
    end
  end
end
