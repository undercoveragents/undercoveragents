# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::MissionTriggers" do
  let(:mission) { create(:mission) }

  describe "GET /admin/missions/:mission_id/automation" do
    it "returns ok" do
      get admin_mission_mission_triggers_path(mission)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Automation")
    end

    it "loads a mission from another operation in the same tenant and adopts its operation" do
      headquarter = default_tenant.headquarter_operation

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_missions_url }
      get admin_mission_mission_triggers_path(mission)

      expect(response).to have_http_status(:ok)
      expect(request.session[:current_operation_id]).to eq(mission.operation_id)
    end
  end

  describe "GET /admin/missions/:mission_id/automation/new" do
    it "renders the trigger type picker when no type is selected" do
      get new_admin_mission_mission_trigger_path(mission)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Schedule", "Webhook")
    end

    it "renders the new form for a valid trigger type" do
      get new_admin_mission_mission_trigger_path(mission, type: "schedule")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Create Trigger")
    end
  end

  describe "GET /admin/missions/:mission_id/automation/:id/edit" do
    it "renders the edit form" do
      mission_trigger = create(:mission_trigger, :webhook, mission:)

      get edit_admin_mission_mission_trigger_path(mission, mission_trigger)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mission_trigger.name)
    end
  end

  describe "POST /admin/missions/:mission_id/automation" do
    it "creates a schedule trigger" do
      expect do
        post admin_mission_mission_triggers_path(mission), params: {
          mission_trigger: {
            trigger_type: "schedule",
            name: "Hourly sync",
            enabled: "1",
            cron_expression: "0 * * * *",
            timezone: "UTC",
            payload: '{"kind":"sync"}',
          },
        }
      end.to change(MissionTrigger, :count).by(1)

      trigger = MissionTrigger.last
      expect(response).to redirect_to(edit_admin_mission_mission_trigger_path(mission, trigger))
      expect(trigger.payload).to eq({ "kind" => "sync" })
    end

    it "creates a webhook trigger and stores a flash secret" do
      post admin_mission_mission_triggers_path(mission), params: {
        mission_trigger: {
          trigger_type: "webhook",
          name: "Inbound webhook",
          enabled: "1",
          payload: '{"source":"external"}',
        },
      }

      expect(response).to redirect_to(edit_admin_mission_mission_trigger_path(mission, MissionTrigger.last))
      expect(flash[:mission_trigger_webhook_secret]).to start_with("mtw_")
    end

    it "re-renders the form when create validation fails" do
      post admin_mission_mission_triggers_path(mission), params: {
        mission_trigger: {
          trigger_type: "schedule",
          name: "",
          enabled: "1",
          cron_expression: "0 * * * *",
          timezone: "UTC",
          payload: '{"kind":"sync"}',
        },
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/missions/:mission_id/automation/:id" do
    it "updates an existing trigger" do
      mission_trigger = create(:mission_trigger, :schedule, mission:, name: "Hourly sync")

      patch admin_mission_mission_trigger_path(mission, mission_trigger), params: {
        mission_trigger: {
          name: "Daily sync",
          enabled: "1",
          cron_expression: "0 9 * * *",
          timezone: "UTC",
          payload: '{"kind":"daily"}',
        },
      }

      expect(response).to redirect_to(edit_admin_mission_mission_trigger_path(mission, mission_trigger))
      expect(mission_trigger.reload.name).to eq("Daily sync")
      expect(mission_trigger.payload).to eq({ "kind" => "daily" })
    end

    it "re-renders the edit form when update validation fails" do
      mission_trigger = create(:mission_trigger, :schedule, mission:)

      patch admin_mission_mission_trigger_path(mission, mission_trigger), params: {
        mission_trigger: {
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

  describe "POST /admin/missions/:mission_id/automation/:id/regenerate_secret" do
    it "rotates the webhook secret" do
      mission_trigger = create(:mission_trigger, :webhook, mission:)
      old_digest = mission_trigger.webhook_secret_digest

      post regenerate_secret_admin_mission_mission_trigger_path(mission, mission_trigger)

      expect(response).to redirect_to(edit_admin_mission_mission_trigger_path(mission, mission_trigger))
      expect(mission_trigger.reload.webhook_secret_digest).not_to eq(old_digest)
      expect(flash[:mission_trigger_webhook_secret]).to start_with("mtw_")
    end
  end

  describe "DELETE /admin/missions/:mission_id/automation/:id" do
    it "deletes the trigger" do
      mission_trigger = create(:mission_trigger, mission:)

      expect do
        delete admin_mission_mission_trigger_path(mission, mission_trigger)
      end.to change(MissionTrigger, :count).by(-1)

      expect(response).to redirect_to(admin_mission_mission_triggers_path(mission))
    end
  end
end
