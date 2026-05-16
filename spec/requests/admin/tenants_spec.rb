# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Tenants", :unauthenticated do
  include ERB::Util

  let(:system_admin) { create(:user, :system_admin, tenant: default_tenant) }

  before do
    sign_in(system_admin)
  end

  describe "GET /admin/tenants" do
    it "lists tenants for system admins" do
      create(:tenant, name: "Acme")

      get admin_tenants_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acme")
    end

    it "renders successfully when no tenants are returned" do
      relation = instance_double(ActiveRecord::Relation, load: [])

      allow(Tenant).to receive(:ordered).and_return(relation)

      get admin_tenants_path

      expect(response).to have_http_status(:ok)
    end

    it "shows each tenant login URL" do
      tenant = create(:tenant, name: "Acme")

      get admin_tenants_path
      expect(response.body).to include(tenant_login_path(tenant))
    end

    it "does not render a current-tenant counter" do
      create(:tenant, name: "Acme")

      get admin_tenants_path

      expect(response.body).not_to match(/>\s*Current\s*</)
      expect(response.body).not_to include("fa-location-crosshairs")
    end

    it "renders tenant resource counts" do
      tenant = create(:tenant, name: "Acme")
      tenant.ensure_core_resources!
      create(:user, tenant:)
      create(:connector, :llm_provider, tenant:)
      operation = tenant.operations.user_managed.first || create(:operation, tenant:)
      agent = create(:agent, operation:, llm_connector: tenant.connectors.first)
      create(:client, tenant:, agent:)

      get admin_tenants_path

      expect(response.body).to include("1 user")
      expect(response.body).to include("2 operations")
      expect(response.body).to include("1 connector")
      expect(response.body).to include("1 client")
    end

    it "hides the delete button for the default tenant and shows the standard confirm text for others" do
      other_tenant = create(:tenant, name: "Zeta Tenant")
      default_delete_selector = [
        "form.button_to[action='#{admin_tenant_path(default_tenant)}']",
        "button[title='Delete Tenant']",
      ].join(" ")
      other_delete_selector = "form.button_to[action='#{admin_tenant_path(other_tenant)}']"
      confirm_text = "Are you sure you want to delete this tenant? This action cannot be undone."

      get admin_tenants_path

      document = Capybara.string(response.body)

      expect(document).to have_css(".badge", text: "Default")
      expect(document).to have_no_css(default_delete_selector)
      expect(document).to have_css(other_delete_selector)
      expect(response.body).to include(confirm_text)
    end

    it "redirects tenant admins back to the dashboard" do
      sign_in(create(:user, :admin, tenant: default_tenant))

      get admin_tenants_path

      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "GET /admin/tenants/new" do
    it "renders the new form" do
      get new_admin_tenant_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Admin Email")
    end
  end

  describe "GET /admin/tenants/:id/edit" do
    it "renders the edit form" do
      tenant = create(:tenant)

      get edit_admin_tenant_path(tenant)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/tenants" do
    let(:valid_params) do
      {
        tenant: {
          name: "Northwind",
          description: "Customer-facing workspace",
          admin_email: "owner@northwind.test",
        },
      }
    end

    it "creates the tenant, its core operations, and the initial tenant admin record" do
      expect do
        post admin_tenants_path, params: valid_params
      end.to(
        change(Tenant, :count).by(1)
          .and(change(Operation, :count).by(2))
          .and(change(User, :count).by(1)),
      )

      expect(response).to redirect_to(admin_tenants_path)
    end

    it "stores the provisioned admin credentials in the flash" do
      post admin_tenants_path, params: valid_params

      tenant = Tenant.find_by!(name: "Northwind")
      credentials = flash[:tenant_admin_credentials].with_indifferent_access
      admin_user = tenant.users.find_by!(role: "admin")

      expect(credentials[:tenant_name]).to eq("Northwind")
      expect(credentials[:email]).to eq("owner@northwind.test")
      expect(admin_user.email).to eq("owner@northwind.test")
      expect(admin_user).to be_active
      expect(admin_user.authenticate(credentials[:password])).to eq(admin_user)
    end

    it "shows the generated credentials only on the post-create redirect" do
      post admin_tenants_path, params: valid_params

      credentials = flash[:tenant_admin_credentials].with_indifferent_access

      follow_redirect!

      expect(response.body).to include(credentials[:email])
      expect(response.body).to include(html_escape(credentials[:password]))
      expect(response.body).to include("shown only once")

      get admin_tenants_path

      expect(response.body).not_to include(html_escape(credentials[:password]))
    end

    it "renders errors when the admin email is blank" do
      post admin_tenants_path, params: {
        tenant: {
          name: "Northwind",
          description: "Customer-facing workspace",
          admin_email: "",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Admin email")
    end

    it "renders non-email initial admin errors on the tenant form" do
      invalid_admin = User.new(
        tenant: default_tenant,
        email: "owner@northwind.test",
        password: "Password123!",
        role: nil,
        status: nil,
      )

      allow_any_instance_of(Tenant).to receive(:build_initial_admin).and_return(invalid_admin) # rubocop:disable RSpec/AnyInstance

      post admin_tenants_path, params: valid_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(html_escape("Role can't be blank"))
    end

    it "renders errors for invalid input" do
      post admin_tenants_path, params: { tenant: { name: "", description: "Broken" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/tenants/:id" do
    let(:tenant) { create(:tenant, name: "Old Name") }

    it "updates the tenant" do
      patch admin_tenant_path(tenant), params: { tenant: { name: "New Name", description: tenant.description } }

      expect(response).to redirect_to(admin_tenants_path)
      expect(tenant.reload.name).to eq("New Name")
    end

    it "renders errors for invalid input" do
      patch admin_tenant_path(tenant), params: { tenant: { name: "", description: tenant.description } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/tenants/:id" do
    it "deletes destroyable tenants" do
      tenant = create(:tenant)

      expect do
        delete admin_tenant_path(tenant)
      end.to change(Tenant, :count).by(-1)

      expect(response).to redirect_to(admin_tenants_path)
    end

    it "deletes tenants even when no current tenant is resolved afterward" do
      tenant = create(:tenant)
      allow_any_instance_of(Admin::TenantsController).to receive(:current_tenant).and_return(nil) # rubocop:disable RSpec/AnyInstance

      delete admin_tenant_path(tenant)

      expect(response).to redirect_to(admin_tenants_path)
    end

    it "refuses to delete the default tenant" do
      expect do
        delete admin_tenant_path(default_tenant)
      end.not_to change(Tenant, :count)

      expect(response).to redirect_to(admin_tenants_path)
    end

    it "purges tenant-owned data before deleting the tenant" do
      resources = build_owned_tenant
      tenant = resources.fetch(:tenant)

      expect do
        delete admin_tenant_path(tenant)
      end.to change(Tenant, :count).by(-1)

      expect(response).to redirect_to(admin_tenants_path)
      expect([
               User.exists?(resources.fetch(:user).id),
               Connector.exists?(tenant_id: tenant.id),
               Operation.exists?(tenant_id: tenant.id),
             ]).to all(be(false))
    end
  end

  def build_owned_tenant
    tenant = create(:tenant, name: "Zeta Tenant")
    tenant.ensure_core_resources!
    operation = tenant.default_operation
    connector = create(:connector, :llm_provider, tenant:)
    user = create(:user, :admin, tenant:)
    agent = create(:agent, operation:, llm_connector: connector)
    mission = create(:mission, operation:)

    create(:client, agent:, tenant:)
    create(:api_client, tenant:)
    create(:tool, :rag_query, operation:)
    create(:skill_catalog, operation:)
    create(:rag_flow, operation:)
    create(:system_preference, tenant:, llm_connector: connector, model_id: "gpt-4.1")
    create(:chat, user:, agent:, mission:)
    create(:test_suite, agent:)

    { tenant:, user: }
  end
end
