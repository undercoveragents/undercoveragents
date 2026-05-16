# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Operations" do
  describe "GET /admin/operations" do
    it "returns a successful response" do
      get admin_operations_path
      expect(response).to have_http_status(:ok)
    end

    it "shows operations including the default" do
      get admin_operations_path
      expect(response.body).to include("Default")
    end

    context "with existing operations" do
      it "lists operations" do
        create(:operation, name: "Alpha Team")
        create(:operation, name: "Beta Team")
        get admin_operations_path
        expect(response.body).to include("Alpha Team")
        expect(response.body).to include("Beta Team")
      end
    end

    context "when non-admin" do
      before do
        non_admin = create(:user, role: "user")
        post sessions_path, params: { email: non_admin.email, password: "Password123!" }
      end

      it "redirects to the root path" do
        get admin_operations_path

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET /admin/operations/new" do
    it "returns a successful response" do
      get new_admin_operation_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the operation form" do
      get new_admin_operation_path
      expect(response.body).to include("New Operation")
    end
  end

  describe "POST /admin/operations" do
    let(:valid_params) do
      { operation: { name: "Test Operation", description: "A test op" } }
    end

    context "with valid params" do
      it "creates a new operation" do
        expect do
          post admin_operations_path, params: valid_params
        end.to change(Operation, :count).by(1)
      end

      it "redirects to index" do
        post admin_operations_path, params: valid_params
        expect(response).to redirect_to(admin_operations_path)
      end
    end

    context "with invalid params" do
      it "does not create an operation" do
        expect do
          post admin_operations_path, params: { operation: { name: "" } }
        end.not_to change(Operation, :count)
      end
    end
  end

  describe "GET /admin/operations/:id/edit" do
    it "returns a successful response" do
      operation = create(:operation)
      get edit_admin_operation_path(operation)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/operations/:id" do
    let(:operation) { create(:operation) }

    it "updates the operation" do
      patch admin_operation_path(operation), params: { operation: { name: "Updated Name" } }
      expect(operation.reload.name).to eq("Updated Name")
    end

    it "redirects to index" do
      patch admin_operation_path(operation), params: { operation: { name: "Updated Name" } }
      expect(response).to redirect_to(admin_operations_path)
    end

    context "with invalid params" do
      it "re-renders the edit form" do
        patch admin_operation_path(operation), params: { operation: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /admin/operations/:id" do
    it "deletes a user-managed operation" do
      operation = create(:operation)
      expect do
        delete admin_operation_path(operation)
      end.to change(Operation, :count).by(-1)
    end

    it "does not delete a system operation" do
      operation = create(:operation, :system)
      expect do
        delete admin_operation_path(operation)
      end.not_to change(Operation, :count)
    end

    it "redirects with alert when trying to delete a system operation" do
      operation = create(:operation, :system)
      delete admin_operation_path(operation)
      expect(response).to redirect_to(admin_operations_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("operations.cannot_delete_system"))
    end

    it "resets session to default when deleting the active operation" do
      operation = create(:operation)
      # Switch to this operation first
      post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_operations_url }
      # Then delete it
      delete admin_operation_path(operation)
      expect(response).to redirect_to(admin_operations_path)
    end

    it "clears the active operation when no default operation is available" do
      operation = create(:operation)
      post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_operations_url }
      allow_any_instance_of(Tenant).to receive(:default_operation).and_return(nil) # rubocop:disable RSpec/AnyInstance

      delete admin_operation_path(operation)

      expect(response).to redirect_to(admin_operations_path)
    end
  end

  describe "POST /admin/operations/:id/switch" do
    it "sets the current operation in session" do
      operation = create(:operation)
      post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_operations_url }
      expect(response).to redirect_to(admin_operations_url)
    end

    it "redirects to an explicit target when provided" do
      operation = create(:operation)

      post switch_admin_operation_path(operation), params: {
        redirect_to: admin_root_path(operation: operation.slug),
      }

      expect(response).to redirect_to(admin_root_path(operation: operation.slug))
    end
  end
end
