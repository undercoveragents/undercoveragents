# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cloud signups", :unauthenticated do
  describe "GET /try-in-cloud" do
    it "renders the onboarding page" do
      get new_cloud_signup_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create workspace")
      expect(response.body).not_to include("Workspace name")
    end

    it "redirects signed-in users to their default app path" do
      user = create(:user, :admin)
      sign_in(user)

      get new_cloud_signup_path

      expect(response).to redirect_to(admin_root_path)
    end

    it "shows the Google action when Google auth is enabled" do
      create(:connectors_authentication, :google, enabled: true)

      get new_cloud_signup_path

      expect(response.body).to include("Continue with Google")
    end
  end

  describe "POST /try-in-cloud" do
    it "creates a tenant admin and signs in" do
      expect do
        post cloud_signup_path, params: {
          cloud_signup: {
            admin_email: "founder@acme.test",
            password: "Validpass1!",
            password_confirmation: "Validpass1!",
          },
        }
      end.to change(Tenant, :count).by(1).and change(User, :count).by(1)

      tenant = Tenant.find_by!(name: "founder workspace")
      user = User.find_by!(email: "founder@acme.test")

      expect(user.tenant).to eq(tenant)
      expect(user).to be_admin
      expect(response).to redirect_to(admin_root_path)
    end

    it "renders errors when the signup is invalid" do
      post cloud_signup_path, params: {
        cloud_signup: {
          admin_email: "not-an-email",
          password: "short",
          password_confirmation: "mismatch",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("prevented this workspace from being saved")
    end
  end
end
