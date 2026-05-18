# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationController do
  controller do
    skip_before_action :require_authentication

    def index
      head :ok
    end
  end

  before do
    routes.draw { get "index" => "anonymous#index" }
    Current.reset
  end

  after do
    Current.reset
  end

  describe "tenant resolution" do
    it "returns nil when no user is signed in" do
      get :index

      expect(controller.send(:current_tenant)).to be_nil
    end

    it "uses the current user's tenant" do
      user = create(:user)
      allow(controller).to receive(:current_user).and_return(user)

      expect(controller.send(:current_tenant)).to eq(user.tenant)
    end

    it "ignores stale tenant session state for system admins" do
      user = build(:user, :system_admin, tenant: create(:tenant))
      session[:current_tenant_id] = -1
      allow(controller).to receive(:current_user).and_return(user)

      expect(controller.send(:resolve_current_tenant)).to eq(user.tenant)
    end

    it "handles a signed-in user without a resolved tenant" do
      user = instance_double(User, tenant: nil, system_admin?: false)
      allow(controller).to receive_messages(current_user: user, resolve_current_tenant: nil)

      expect(controller.send(:current_tenant)).to be_nil
    end
  end

  describe "operation resolution" do
    it "returns nil when no current tenant is available" do
      allow(controller).to receive(:current_tenant).and_return(nil)

      expect(controller.send(:current_operation)).to be_nil
      expect(session[:current_operation_id]).to be_nil
    end

    it "handles a missing resolved operation even when a tenant is present" do
      allow(controller).to receive_messages(current_tenant: create(:tenant), resolve_current_operation: nil)

      expect(controller.send(:current_operation)).to be_nil
      expect(session[:current_operation_id]).to be_nil
    end

    it "ensures and stores the default operation for the current tenant" do
      tenant = create(:tenant)
      allow(controller).to receive(:current_tenant).and_return(tenant)

      operation = controller.send(:current_operation)

      expect(operation).to eq(tenant.reload.default_operation)
      expect(session[:current_operation_id]).to eq(operation.id)
    end

    it "returns nil when no operation is selected in the session" do
      tenant = create(:tenant)
      allow(controller).to receive(:current_tenant).and_return(tenant)

      expect(controller.send(:selected_current_operation)).to be_nil
    end

    it "returns nil when the stored operation id does not belong to the current tenant" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      session[:current_operation_id] = -1
      allow(controller).to receive(:current_tenant).and_return(tenant)

      expect(controller.send(:selected_current_operation)).to be_nil
    end
  end

  describe "scope helpers" do
    before do
      allow(controller).to receive_messages(current_tenant: nil, current_operation: nil)
    end

    it "returns empty operation-scoped relations when no operation is selected" do
      expect(controller.send(:scoped_agents)).to be_empty
      expect(controller.send(:scoped_missions)).to be_empty
      expect(controller.send(:scoped_tools)).to be_empty
      expect(controller.send(:scoped_skill_catalogs)).to be_empty
      expect(controller.send(:scoped_rag_flows)).to be_empty
    end

    it "returns empty tenant-owned relations when no tenant is selected" do
      expect(controller.send(:scoped_operations)).to be_empty
      expect(controller.send(:scoped_connectors)).to be_empty
      expect(controller.send(:scoped_channels)).to be_empty
      expect(controller.send(:scoped_clients)).to be_empty
      expect(controller.send(:scoped_api_clients)).to be_empty
    end

    it "returns tenant-owned relations when a tenant is selected" do
      tenant = create(:tenant)
      other_tenant = create(:tenant)
      visible_operation = create(:operation, tenant:)
      visible_agent = create(:agent, operation: visible_operation)
      other_operation = create(:operation, tenant: other_tenant)
      other_agent = create(:agent, operation: other_operation)
      visible_client = create(:client, tenant:, agent: visible_agent)
      visible_api_client = create(:api_client, tenant:)
      create(:client, tenant: other_tenant, agent: other_agent)
      create(:api_client, tenant: other_tenant)

      allow(controller).to receive(:current_tenant).and_return(tenant)

      expect(controller.send(:scoped_clients)).to contain_exactly(visible_client)
      expect(controller.send(:scoped_api_clients)).to contain_exactly(visible_api_client)
    end

    it "returns empty tenant-derived activity relations when no tenant is selected" do
      expect(controller.send(:tenant_scoped_test_suites)).to be_empty
      expect(controller.send(:tenant_scoped_mission_runs)).to be_empty
      expect(controller.send(:tenant_scoped_chats)).to be_empty
    end
  end

  describe "request context" do
    it "stores the operation only for admin paths" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      operation = tenant.default_operation
      user = build(:user, tenant:)

      allow(controller).to receive_messages(
        current_user: user,
        current_tenant: tenant,
        current_operation: operation,
      )
      allow(request).to receive(:path).and_return("/admin")

      controller.send(:set_current_request_context)

      expect(Current.user).to eq(user)
      expect(Current.tenant).to eq(tenant)
      expect(Current.operation).to eq(operation)
    end

    it "does not store the operation for non-admin paths" do
      tenant = create(:tenant)
      tenant.ensure_core_resources!
      operation = tenant.default_operation
      user = build(:user, tenant:)

      allow(controller).to receive_messages(
        current_user: user,
        current_tenant: tenant,
        current_operation: operation,
      )
      allow(request).to receive(:path).and_return("/chat")

      controller.send(:set_current_request_context)

      expect(Current.user).to eq(user)
      expect(Current.tenant).to eq(tenant)
      expect(Current.operation).to be_nil
    end
  end

  describe "preview channel helpers" do
    it "derives the preview channel id from the admin channel preview route" do
      preview_params = ActionController::Parameters.new(
        id: "preview-123",
        view: "preview",
      )
      allow(controller).to receive_messages(
        controller_path: "admin/channels",
        action_name: "show",
        params: preview_params,
      )

      expect(controller.send(:preview_channel_id_from_admin_show)).to eq("preview-123")
    end
  end

  describe "agent alpha helpers" do
    it "always uses Agent Alpha as the display name" do
      expect(controller.send(:agent_alpha_display_name)).to eq("Agent Alpha")
    end

    it "reports Agent Alpha as unconfigured when no tenant is resolved" do
      allow(controller).to receive(:current_tenant).and_return(nil)

      expect(controller.send(:agent_alpha_configured?)).to be(false)
    end

    it "returns nil for the header chat when the user or tenant is missing" do
      allow(controller).to receive_messages(current_user: nil, current_tenant: create(:tenant))

      expect(controller.send(:current_agent_alpha_chat_for_header)).to be_nil
    end

    it "prefers the remembered Agent Alpha application chat for the header" do
      tenant = create(:tenant)
      user = create(:user, tenant:)
      operation = create(:operation, tenant:)
      agent = create(:agent, operation:, builtin: true, builtin_key: "agent_alpha")
      older_chat = create(:chat, :application_context, user:, agent:, updated_at: 1.day.ago)
      create(:chat, :application_context, user:, agent:, updated_at: Time.current)
      session[:admin_agent_alpha_chat_id] = older_chat.id

      allow(controller).to receive_messages(current_user: user, current_tenant: tenant)
      allow(Agent).to receive(:find_builtin_by_key).with("agent_alpha", tenant:).and_return(agent)

      expect(controller.send(:current_agent_alpha_chat_for_header)).to eq(older_chat)
    end
  end
end
