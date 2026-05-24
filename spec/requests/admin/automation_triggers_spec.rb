# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AutomationTriggers" do
  let(:rag_flow) { create(:rag_flow) }

  describe "GET /admin/rag_flows/:rag_flow_id/automation" do
    it "returns ok and adopts the rag flow operation" do
      headquarter = default_tenant.headquarter_operation

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_rag_flows_url }
      get admin_rag_flow_automation_triggers_path(rag_flow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Automation")
      expect(request.session[:current_operation_id]).to eq(rag_flow.operation_id)
    end
  end

  describe "GET /admin/rag_flows/:rag_flow_id/automation/new" do
    it "renders the trigger type picker when no type is selected" do
      get new_admin_rag_flow_automation_trigger_path(rag_flow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Schedule", "Webhook")
    end

    it "renders the new form for a valid trigger type" do
      get new_admin_rag_flow_automation_trigger_path(rag_flow, type: "schedule")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Trigger")
    end
  end

  describe "CRUD actions" do
    let(:trigger) do
      create(:automation_trigger, :webhook, target: rag_flow)
    end

    it "creates a rag-flow automation trigger via POST" do
      expect do
        post admin_rag_flow_automation_triggers_path(rag_flow), params: {
          automation_trigger: {
            trigger_type: "webhook",
            name: "RAG Webhook",
            enabled: "1",
            payload: '{"source":"external"}',
          },
        }
      end.to change(AutomationTrigger, :count).by(1)

      created = AutomationTrigger.last
      expect(response).to redirect_to(edit_admin_rag_flow_automation_trigger_path(rag_flow, created))
      expect(flash[:automation_trigger_webhook_secret]).to start_with("atw_")
    end

    it "updates a rag-flow automation trigger via PATCH" do
      patch admin_rag_flow_automation_trigger_path(rag_flow, trigger), params: {
        automation_trigger: {
          name: "Nightly refresh",
          enabled: "1",
          cron_expression: "0 2 * * *",
          timezone: "UTC",
          payload: '{"kind":"nightly"}',
        },
      }

      expect(response).to redirect_to(edit_admin_rag_flow_automation_trigger_path(rag_flow, trigger))
      expect(trigger.reload.name).to eq("Nightly refresh")
    end

    it "rotates the webhook secret" do
      old_digest = trigger.webhook_secret_digest
      post regenerate_secret_admin_rag_flow_automation_trigger_path(rag_flow, trigger)
      expect(trigger.reload.webhook_secret_digest).not_to eq(old_digest)
    end

    it "deletes the rag-flow automation trigger" do
      trigger # ensure created
      expect do
        delete admin_rag_flow_automation_trigger_path(rag_flow, trigger)
      end.to change(AutomationTrigger, :count).by(-1)
      expect(response).to redirect_to(admin_rag_flow_automation_triggers_path(rag_flow))
    end

    it "re-renders the form when validation fails" do
      post admin_rag_flow_automation_triggers_path(rag_flow), params: {
        automation_trigger: {
          trigger_type: "schedule",
          name: "",
          enabled: "1",
          cron_expression: "0 * * * *",
          timezone: "UTC",
          payload: "{}",
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
