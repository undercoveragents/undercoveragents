# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::MissionControl::Runs" do
  def response_document
    response.parsed_body
  end

  describe "GET /admin/mission_control/runs" do
    it "lists only runs from the current tenant" do
      own_mission = create(:mission, operation: default_operation, name: "Tenant Mission")
      foreign_tenant = create(:tenant, name: "Foreign Tenant")
      foreign_operation = create(:operation, tenant: foreign_tenant, name: "Foreign Operation")
      foreign_mission = create(:mission, operation: foreign_operation, name: "Foreign Mission")
      create(:mission_run, mission: own_mission)
      create(:mission_run, mission: foreign_mission)

      get admin_mission_control_runs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(own_mission.name)
      expect(response.body).not_to include(foreign_mission.name)
    end

    it "renders run rows without hard-navigation onclick handlers", :aggregate_failures do
      mission = create(:mission, operation: default_operation, name: "Tenant Mission")
      run = create(:mission_run, mission:)

      get admin_mission_control_runs_path

      row = response_document.at_css("tr.mc-tr")
      title_link = response_document.at_css("a[href='#{admin_mission_control_run_path(run)}']")

      expect(row).to be_present
      expect(row["onclick"]).to be_nil
      expect(title_link).to be_present
    end
  end
end
