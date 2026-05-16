# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions", :unauthenticated do
  describe "GET /login" do
    it "renders the login page" do
      get new_session_path
      expect(response).to have_http_status(:ok)
    end

    it "does not show the Try in Cloud link" do
      get new_session_path

      expect(response.body).not_to include("Try in Cloud")
    end

    it "shows Google sign-in when Google auth is enabled" do
      create(:connectors_authentication, :google, enabled: true)

      get new_session_path

      expect(response.body).to include("Sign in with Google")
    end

    it "redirects to root when already signed in" do
      user = create(:user)
      post sessions_path, params: { email: user.email, password: "Password123!" }

      get new_session_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /tenants/:tenant_id/login" do
    it "renders the same generic login UI" do
      tenant = create(:tenant, name: "Northwind")

      get tenant_login_path(tenant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign In")
      expect(response.body).not_to include("Northwind")
      expect(response.body).not_to include("System admin login")
      expect(response.body).not_to include("This sign-in page only accepts local accounts")
    end

    it "shows Google sign-in on tenant-scoped login pages" do
      tenant = create(:tenant, name: "Northwind")
      create(:connectors_authentication, :google, enabled: true)

      get tenant_login_path(tenant)

      expect(response.body).to include("Sign in with Google")
    end
  end

  describe "POST /login" do
    let(:user) { create(:user, email: "user@test.com", password: "Validpass1!") }

    before { user }

    context "with valid credentials" do
      it "signs in and redirects to root" do
        post sessions_path, params: { email: "user@test.com", password: "Validpass1!" }
        expect(response).to redirect_to(root_path)
      end

      it "signs in as admin and redirects to admin root" do
        admin = create(:user, :admin, email: "admin@test.com", password: "Validpass1!")
        post sessions_path, params: { email: admin.email, password: "Validpass1!" }
        expect(response).to redirect_to(admin_root_path)
      end

      it "shows success notice" do
        post sessions_path, params: { email: "user@test.com", password: "Validpass1!" }
        follow_redirect!
        expect(response.body).to include("Signed in successfully")
      end

      it "is case-insensitive for email" do
        post sessions_path, params: { email: "USER@TEST.COM", password: "Validpass1!" }
        expect(response).to redirect_to(root_path)
      end

      it "redirects to return_to path when set" do
        get admin_agents_path
        post sessions_path, params: { email: "user@test.com", password: "Validpass1!" }
        expect(response).to redirect_to(admin_agents_path)
      end

      it "signs in even when the tenant has no default operation" do
        allow_any_instance_of(Tenant).to receive(:default_operation).and_return(nil) # rubocop:disable RSpec/AnyInstance

        post sessions_path, params: { email: "user@test.com", password: "Validpass1!" }

        expect(response).to redirect_to(root_path)
      end

      it "signs in through the tenant-specific login page for matching accounts" do
        tenant = create(:tenant, name: "Northwind")
        scoped_user = create(:user, tenant:, email: "scoped@test.com", password: "Validpass1!")

        post tenant_login_path(tenant), params: { email: scoped_user.email, password: "Validpass1!" }

        expect(response).to redirect_to(root_path)
      end

      it "signs in a user from another tenant through the generic login page" do
        tenant = create(:tenant, name: "Northwind")
        scoped_user = create(:user, tenant:, email: "scoped@test.com", password: "Validpass1!")

        post sessions_path, params: { email: scoped_user.email, password: "Validpass1!" }

        expect(response).to redirect_to(root_path)
      end
    end

    context "with invalid credentials" do
      it "renders login page with error" do
        post sessions_path, params: { email: "user@test.com", password: "wrongpass" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects accounts from other tenants on a tenant-specific login page" do
        tenant = create(:tenant, name: "Northwind")

        post tenant_login_path(tenant), params: { email: "user@test.com", password: "Validpass1!" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Sign In")
        expect(response.body).not_to include("Northwind")
      end

      it "handles nil email gracefully" do
        post sessions_path, params: { password: "whatever" }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with inactive account" do
      let(:user) { create(:user, :inactive, email: "inactive@test.com", password: "Validpass1!") }

      it "renders login page with inactive message" do
        post sessions_path, params: { email: "inactive@test.com", password: "Validpass1!" }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "OAuth context" do
    it "stores the tenant-scoped OAuth login context on the tenant login page" do
      tenant = create(:tenant)

      get tenant_login_path(tenant)

      expect(request.session[:oauth_login_tenant_id]).to eq(tenant.id)
    end

    it "clears the tenant-scoped OAuth login context on the generic login page" do
      tenant = create(:tenant)
      get tenant_login_path(tenant)

      get new_session_path

      expect(request.session[:oauth_login_tenant_id]).to be_nil
    end

    it "clears the pending cloud signup context on the login page" do
      get new_cloud_signup_path
      request.session[Cloud::PendingSignup::SESSION_KEY] = {
        "provider" => "google",
      }

      get new_session_path

      expect(request.session[Cloud::PendingSignup::SESSION_KEY]).to be_nil
    end
  end

  describe "DELETE /logout" do
    it "signs out and redirects to login" do
      user = create(:user)
      post sessions_path, params: { email: user.email, password: "Password123!" }

      delete session_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "authentication required" do
    it "redirects unauthenticated requests to login" do
      get root_path
      expect(response).to redirect_to(new_session_path)
    end
  end
end
