# frozen_string_literal: true

require "rails_helper"

RSpec.describe "RagFlows" do
  describe "GET /rag_flows (standalone)" do
    it "returns a successful response when no rag flows exist" do
      get admin_rag_flows_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "nested routes" do
    describe "GET /admin/rag_flows" do
      it "returns a successful response" do
        get admin_rag_flows_path
        expect(response).to have_http_status(:ok)
      end

      it "displays the empty state when no rag flows exist" do
        get admin_rag_flows_path
        expect(response.body).to include("No RAG yet")
      end

      context "with existing rag flows" do
        it "lists RAG" do
          create(:rag_flow, name: "KB Loader")

          get admin_rag_flows_path
          expect(response.body).to include("KB Loader")
        end
      end
    end

    describe "GET /admin/rag_flows/new" do
      it "returns a successful response" do
        get new_admin_rag_flow_path
        expect(response).to have_http_status(:ok)
      end

      it "displays the new form" do
        get new_admin_rag_flow_path
        expect(response.body).to include("New RAG")
      end
    end

    describe "POST /admin/rag_flows" do
      it "creates a new RAG" do
        expect do
          post admin_rag_flows_path, params: {
            rag_flow: { name: "My Pipeline" },
          }
        end.to change(RagFlow, :count).by(1)
      end

      it "redirects to the show page on success" do
        post admin_rag_flows_path, params: {
          rag_flow: { name: "My Pipeline" },
        }
        expect(response).to redirect_to(admin_rag_flow_path(RagFlow.last))
      end

      it "renders new on validation errors" do
        post admin_rag_flows_path, params: {
          rag_flow: { name: "" },
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "GET /...rag_flows/:id" do
      let(:ip) { create(:rag_flow) }

      it "returns a successful response" do
        get admin_rag_flow_path(ip)
        expect(response).to have_http_status(:ok)
      end

      it "displays the rag flow name" do
        get admin_rag_flow_path(ip)
        expect(response.body).to include(ip.name)
      end

      it "renders gracefully when a configured step references an unknown module" do
        create(
          :rag_step,
          rag_flow: ip,
          stage: "chunking",
          module_type: "removed_chunker_plugin",
          configuration: {},
        )

        get admin_rag_flow_path(ip)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Unknown module")
      end
    end

    describe "GET /...rag_flows/:id/edit" do
      let(:ip) { create(:rag_flow) }

      it "returns a successful response" do
        get edit_admin_rag_flow_path(ip)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /...rag_flows/:id" do
      let(:ip) { create(:rag_flow, name: "Old Name") }

      it "updates the rag flow" do
        patch admin_rag_flow_path(ip), params: {
          rag_flow: { name: "New Name" },
        }
        expect(ip.reload.name).to eq("New Name")
      end

      it "redirects to show on success" do
        patch admin_rag_flow_path(ip), params: {
          rag_flow: { name: "New Name" },
        }
        ip.reload
        expect(response).to redirect_to(admin_rag_flow_path(ip))
      end

      it "renders edit with unprocessable_content on validation failure" do
        patch admin_rag_flow_path(ip), params: {
          rag_flow: { name: "" },
        }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "DELETE /...rag_flows/:id" do
      let!(:ip) { create(:rag_flow) }

      it "deletes the rag flow" do
        expect do
          delete admin_rag_flow_path(ip)
        end.to change(RagFlow, :count).by(-1)
      end

      it "redirects to index" do
        delete admin_rag_flow_path(ip)
        expect(response).to redirect_to(admin_rag_flows_path)
      end
    end

    describe "PATCH /...rag_flows/:id/toggle" do
      let(:ip) { create(:rag_flow, enabled: true) }

      it "toggles the enabled state from true to false" do
        patch toggle_admin_rag_flow_path(ip)
        expect(ip.reload.enabled?).to be(false)
      end

      it "toggles the enabled state from false to true" do
        ip.update!(enabled: false)
        patch toggle_admin_rag_flow_path(ip)
        expect(ip.reload.enabled?).to be(true)
      end
    end

    describe "POST /...rag_flows/:id/execute" do
      let(:ip) { create(:rag_flow, enabled: true) }

      context "when rag flow is runnable" do
        it "enqueues the execution job" do
          expect do
            post execute_admin_rag_flow_path(ip)
          end.to have_enqueued_job(Rag::ExecutionJob)

          expect(Rag::ExecutionJob).to have_been_enqueued.with(
            ip.id,
            tenant_id: ip.operation.tenant_id,
            triggered_by: "manual",
            run_id: ip.rag_runs.order(:created_at).last.id,
          )
        end

        it "redirects to run page" do
          post execute_admin_rag_flow_path(ip)
          run = ip.rag_runs.order(:created_at).last
          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(admin_rag_flow_run_path(ip, run))
        end
      end

      context "when rag flow is not runnable" do
        let(:ip) { create(:rag_flow, enabled: true) }

        before do
          ip
          # rubocop:disable RSpec/AnyInstance
          allow_any_instance_of(Admin::RagFlowsController).to receive(:authorize).and_return(true)
          allow_any_instance_of(RagFlow).to receive(:runnable?).and_return(false)
          # rubocop:enable RSpec/AnyInstance
        end

        it "redirects with alert" do
          post execute_admin_rag_flow_path(ip)
          expect(response).to redirect_to(admin_rag_flow_path(ip))
          expect(flash[:alert]).to eq("Flow must be enabled to run.")
        end
      end
    end
  end
end
