# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users" do
  def parsed_response
    response.parsed_body
  end

  describe "GET /admin/users" do
    it "lists all users" do
      create(:user, email: "other@test.com")
      get admin_users_path
      expect(response).to have_http_status(:ok)
    end

    it "limits system admins to users in their current tenant" do
      other_tenant = create(:tenant)
      current_tenant_user = create(:user, email: "same-tenant@test.com", tenant: default_tenant)
      other_tenant_user = create(:user, email: "other-tenant@test.com", tenant: other_tenant)
      sign_in(create(:user, :system_admin, tenant: default_tenant))

      get admin_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(current_tenant_user.email)
      expect(response.body).not_to include(other_tenant_user.email)
    end

    it "does not render a tenant column" do
      get admin_users_path

      headers = parsed_response.css("table thead th").map { |node| node.text.strip }
      expect(headers).not_to include("Tenant")
    end

    context "when non-admin" do
      before do
        non_admin = create(:user, role: "user")
        post sessions_path, params: { email: non_admin.email, password: "Password123!" }
      end

      it "redirects with error" do
        get admin_users_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when unauthenticated (current_user is nil)", :unauthenticated do
      it "redirects to login with an alert (nil safe-nav on current_user)" do
        get admin_users_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "GET /admin/users/new" do
    it "renders the new user form" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
    end

    it "does not render a tenant selector for system admins" do
      sign_in(create(:user, :system_admin, tenant: default_tenant))

      get new_admin_user_path

      expect(parsed_response.at_css('select[name="user[tenant_id]"]')).to be_nil
      expect(response.body).to include("System admin")
    end
  end

  describe "POST /admin/users" do
    let(:valid_params) do
      { user: { email: "newuser@test.com", password: "Securepass1!", role: "user", status: "active" } }
    end

    it "creates a new user" do
      expect { post admin_users_path, params: valid_params }.to change(User, :count).by(1)
    end

    it "redirects to users list" do
      post admin_users_path, params: valid_params
      expect(response).to redirect_to(admin_users_path)
    end

    it "defaults system-admin created users to the current tenant" do
      sign_in(create(:user, :system_admin, tenant: default_tenant))
      other_tenant = create(:tenant)

      post admin_users_path, params: {
        user: {
          email: "system-admin-created@test.com",
          password: "Securepass1!",
          role: "system_admin",
          status: "active",
          tenant_id: other_tenant.id,
        },
      }

      created_user = User.find_by!(email: "system-admin-created@test.com")
      expect(created_user.role).to eq("system_admin")
      expect(created_user.tenant).to eq(default_tenant)
    end

    it "normalizes invalid roles and ignores foreign tenant ids for tenant admins" do
      other_tenant = create(:tenant)

      post admin_users_path, params: {
        user: {
          email: "tenant-admin-created@test.com",
          password: "Securepass1!",
          role: "system_admin",
          status: "active",
          tenant_id: other_tenant.id,
        },
      }

      created_user = User.find_by!(email: "tenant-admin-created@test.com")
      expect(created_user.role).to eq("user")
      expect(created_user.tenant).to eq(default_tenant)
    end

    context "with invalid params" do
      it "renders the form with errors" do
        post admin_users_path, params: { user: { email: "", password: "", role: "user", status: "active" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "GET /admin/users/:id/edit" do
    it "renders the edit form" do
      user = create(:user)
      get edit_admin_user_path(user)
      expect(response).to have_http_status(:ok)
    end

    it "does not allow system admins to edit users from another tenant" do
      sign_in(create(:user, :system_admin, tenant: default_tenant))
      foreign_user = create(:user, tenant: create(:tenant))

      get edit_admin_user_path(foreign_user)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/users/:id" do
    let!(:user) { create(:user, email: "old@test.com") }

    it "updates the user" do
      patch admin_user_path(user), params: { user: { email: "new@test.com", role: "user", status: "active" } }
      expect(user.reload.email).to eq("new@test.com")
    end

    it "ignores blank password" do
      old_digest = user.password_digest
      patch admin_user_path(user),
            params: { user: { email: user.email, password: "", role: "user", status: "active" } }
      expect(user.reload.password_digest).to eq(old_digest)
    end

    it "updates password when a non-blank password is provided" do
      patch admin_user_path(user),
            params: { user: { email: user.email, password: "NewValid123!", role: "user", status: "active" } }
      expect(response).to redirect_to(admin_users_path)
      expect(user.reload.authenticate("NewValid123!")).to be_truthy
    end

    it "redirects to users list" do
      patch admin_user_path(user), params: { user: { email: user.email, role: "user", status: "active" } }
      expect(response).to redirect_to(admin_users_path)
    end

    context "with invalid params" do
      it "renders the edit form with errors" do
        patch admin_user_path(user), params: { user: { email: "", role: "user", status: "active" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /admin/users/:id" do
    it "deletes a user" do
      user = create(:user)
      expect { delete admin_user_path(user) }.to change(User, :count).by(-1)
    end

    it "prevents deleting own user" do
      # sign_in created an admin automatically; find it
      admin = User.find_by(role: "admin")
      delete admin_user_path(admin)
      expect(response).to redirect_to(admin_users_path)
      expect(User.exists?(admin.id)).to be(true)
    end
  end
end
