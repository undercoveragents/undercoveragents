# frozen_string_literal: true

require "rails_helper"

# OmniAuth test mode is used so that no real Keycloak instance is required.
# Setting OmniAuth.config.test_mode = true causes the middleware to intercept
# /auth/:provider/callback and inject the mock auth hash into the rack env.
RSpec.describe "OmniauthCallbacks", :unauthenticated do
  let(:auth_hash_for) do
    lambda do |uid:, email:, provider: "keycloak"|
      OmniAuth::AuthHash.new(
        provider:,
        uid:,
        info: { email: },
      )
    end
  end

  before do
    OmniAuth.config.test_mode = true
  end

  after do
    OmniAuth.config.mock_auth[:keycloak] = nil
    OmniAuth.config.mock_auth[:google] = nil
    OmniAuth.config.test_mode = false
  end

  describe "GET /auth/keycloak/callback" do
    context "when user is found by provider + uid" do
      before do
        create(:user, :oauth, provider: "keycloak", uid: "existing-uid-123",
                              email: "keycloak_user@example.com", status: "active",)
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "existing-uid-123", email: "keycloak_user@example.com",
        )
      end

      it "signs in the existing user and redirects to root" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(root_path)
      end

      it "redirects an admin OAuth user to admin root" do
        create(:user, :admin, :oauth, provider: "keycloak", uid: "admin-uid-999",
                                      email: "admin_oauth@example.com", status: "active",)
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "admin-uid-999", email: "admin_oauth@example.com",
        )

        get "/auth/keycloak/callback"
        expect(response).to redirect_to(admin_root_path)
      end

      it "shows the signed-in notice" do
        get "/auth/keycloak/callback"
        follow_redirect!
        expect(response.body).to include(I18n.t("auth.signed_in"))
      end

      it "stores the user_id in the session" do
        get "/auth/keycloak/callback"
        # Confirm sign-in by fetching an authenticated page
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end
    end

    context "when user exists by email only (OAuth linking)" do
      let!(:local_user) do
        create(:user, email: "linkme@example.com", provider: nil, uid: nil)
      end

      before do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "brand-new-uid-456", email: "linkme@example.com",
        )
      end

      it "does not link the OAuth identity from the generic login page" do
        get "/auth/keycloak/callback"
        local_user.reload
        expect(local_user.provider).to be_nil
        expect(local_user.uid).to be_nil
      end

      it "redirects back to the generic login page" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(new_session_path)
      end

      it "shows guidance to use the workspace login page first" do
        get "/auth/keycloak/callback"

        follow_redirect!
        expect(response.body).to include(I18n.t("auth.oauth_tenant_login_required"))
      end
    end

    context "when no user exists" do
      before do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "totally-new-uid-789", email: "newuser@example.com",
        )
      end

      it "does not create a new user record" do
        expect { get "/auth/keycloak/callback" }.not_to change(User, :count)
      end

      it "redirects back to the generic login page" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(new_session_path)
      end

      it "shows guidance to use the workspace login page first" do
        get "/auth/keycloak/callback"

        follow_redirect!
        expect(response.body).to include(I18n.t("auth.oauth_tenant_login_required"))
      end
    end

    context "when the callback comes from a tenant-scoped login page" do
      let(:tenant) { create(:tenant, name: "Northwind") }

      before do
        get tenant_login_path(tenant)
      end

      it "signs in a matching tenant user by provider and uid" do
        create(
          :user,
          :oauth,
          tenant:,
          provider: "keycloak",
          uid: "tenant-existing-uid",
          email: "scoped-oauth@example.com",
          status: "active",
        )
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "tenant-existing-uid", email: "other-email@example.com",
        )

        get "/auth/keycloak/callback"

        expect(response).to redirect_to(root_path)
      end

      it "links and signs in a matching tenant user by email" do
        user = create(:user, tenant:, email: "scoped@example.com")
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "tenant-uid-123", email: user.email,
        )

        get "/auth/keycloak/callback"

        expect(response).to redirect_to(root_path)
        expect(user.reload.provider).to eq("keycloak")
        expect(user.uid).to eq("tenant-uid-123")
      end

      it "does not create a new user outside the tenant scope" do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "tenant-new-uid", email: "new-tenant-user@example.com",
        )

        expect do
          get "/auth/keycloak/callback"
        end.not_to change(User, :count)

        expect(response).to redirect_to(tenant_login_path(tenant))
      end

      it "does not link a user from another tenant" do
        create(:user, tenant: create(:tenant), email: "foreign@example.com")
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "foreign-tenant-uid", email: "foreign@example.com",
        )

        get "/auth/keycloak/callback"

        expect(response).to redirect_to(tenant_login_path(tenant))
      end

      it "handles nil email safely and redirects back to the tenant login page" do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "tenant-nil-email-uid", email: nil,
        )

        get "/auth/keycloak/callback"

        expect(response).to redirect_to(tenant_login_path(tenant))
      end
    end

    context "when the user exists but is inactive" do
      before do
        create(:user, :oauth, provider: "keycloak", uid: "inactive-uid-000",
                              email: "inactive@example.com", status: "inactive",)
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "inactive-uid-000", email: "inactive@example.com",
        )
      end

      it "redirects to the login page with an error" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(new_session_path)
      end

      it "shows the OAuth error alert" do
        get "/auth/keycloak/callback"
        follow_redirect!
        expect(response.body).to include(I18n.t("auth.oauth_error"))
      end
    end

    context "when an unlinked OAuth account is rejected" do
      before do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "new-uid-unpersisted", email: "unpersisted@example.com",
        )
      end

      it "redirects to the login page with an error" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "when auth info has no email (nil email)" do
      before do
        OmniAuth.config.mock_auth[:keycloak] = auth_hash_for.call(
          uid: "uid-nil-email-999", email: nil,
        )
        allow(User).to receive_messages(find_by: nil, create!: User.new)
      end

      it "does not raise on nil email safe navigation and redirects to login" do
        get "/auth/keycloak/callback"
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "GET /auth/google/callback" do
    before do
      create(:connectors_authentication, :google, enabled: true)
    end

    it "signs in an existing linked Google user from the generic login page" do
      create(
        :user,
        :oauth,
        provider: "google",
        uid: "google-linked-uid",
        email: "owner@orbit.test",
        status: "active",
      )
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-linked-uid",
        email: "owner@orbit.test",
        provider: "google",
      )

      get "/auth/google/callback"

      expect(response).to redirect_to(root_path)
    end

    it "preserves the pending cloud signup across the full Google request and callback roundtrip" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-roundtrip",
        email: "owner@orbit.test",
        provider: "google",
      )

      expect do
        post "/auth/google", params: {
          cloud_signup: {
            flow: Cloud::PendingSignup::FLOW,
          },
        }
        follow_redirect!
      end.to change(Tenant, :count).by(1).and change(User, :count).by(1)

      expect(response).to redirect_to(admin_root_path)
    end

    it "creates a tenant admin from the pending cloud signup" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-123",
        email: "owner@orbit.test",
        provider: "google",
      )

      expect do
        get "/auth/google/callback", params: {
          cloud_signup: {
            flow: Cloud::PendingSignup::FLOW,
          },
        }
      end.to change(Tenant, :count).by(1).and change(User, :count).by(1)

      tenant = Tenant.find_by!(name: "owner workspace")
      user = User.find_by!(email: "owner@orbit.test")

      expect(user.tenant).to eq(tenant)
      expect(user).to be_admin
      expect(response).to redirect_to(admin_root_path)
    end

    it "stores the Google identity on the created tenant admin" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-123",
        email: "owner@orbit.test",
        provider: "google",
      )

      get "/auth/google/callback", params: {
        cloud_signup: {
          flow: Cloud::PendingSignup::FLOW,
        },
      }

      user = User.find_by!(email: "owner@orbit.test")

      expect(user.provider).to eq("google")
      expect(user.uid).to eq("google-uid-123")
    end

    it "does not create a default-tenant user without onboarding or tenant context" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-456",
        email: "no-context@test.com",
        provider: "google",
      )

      expect do
        get "/auth/google/callback"
      end.not_to change(User, :count)

      expect(response).to redirect_to(new_session_path)
    end

    it "does not link a local user from the generic login page" do
      user = create(:user, email: "owner@orbit.test", provider: nil, uid: nil)
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-local-link",
        email: user.email,
        provider: "google",
      )

      get "/auth/google/callback"

      expect(response).to redirect_to(new_session_path)
      expect(user.reload.provider).to be_nil
      expect(user.uid).to be_nil
    end

    it "redirects back to cloud signup when tenant creation fails" do
      create(:user, email: "owner@orbit.test")
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-789",
        email: "owner@orbit.test",
        provider: "google",
      )

      get "/auth/google/callback", params: {
        cloud_signup: {
          flow: Cloud::PendingSignup::FLOW,
        },
      }

      expect(response).to redirect_to(new_cloud_signup_path(email: "owner@orbit.test"))
    end

    it "redirects back to cloud signup without an email param when Google returns no email" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-no-email",
        email: nil,
        provider: "google",
      )

      get "/auth/google/callback", params: {
        cloud_signup: {
          flow: Cloud::PendingSignup::FLOW,
        },
      }

      expect(response).to redirect_to(new_cloud_signup_path)
    end

    it "rejects a mismatched pending signup provider" do
      OmniAuth.config.mock_auth[:google] = auth_hash_for.call(
        uid: "google-uid-999",
        email: "owner@orbit.test",
        provider: "google",
      )
      allow(Cloud::PendingSignup).to receive_messages(
        load: Cloud::PendingSignup::Entry.new(provider: "keycloak"),
        from_request_params: nil,
      )

      get "/auth/google/callback"

      expect(response).to redirect_to(new_cloud_signup_path(email: "owner@orbit.test"))
    end
  end

  describe "GET /auth/failure" do
    it "redirects to the login page" do
      get "/auth/failure", params: { message: "access_denied" }
      expect(response).to redirect_to(new_session_path)
    end

    it "shows a humanized failure message in the alert" do
      get "/auth/failure", params: { message: "access_denied" }
      follow_redirect!
      expect(response.body).to include("Access denied")
    end

    it "handles an empty message param gracefully" do
      get "/auth/failure", params: { message: "" }
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects back to the tenant login page when OAuth fails from a tenant-scoped login" do
      tenant = create(:tenant, name: "Northwind")
      get tenant_login_path(tenant)

      get "/auth/failure", params: { message: "access_denied" }

      expect(response).to redirect_to(tenant_login_path(tenant))
    end
  end
end
