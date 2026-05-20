# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Missions" do
  let!(:mission) { create(:mission) }

  def disabled_debug_flow
    {
      "nodes" => [{ "id" => "n1", "type" => "set_variable", "data" => { "label" => "False Path" } }],
      "edges" => [],
    }
  end

  def disabled_debug_execution_state
    {
      "execution_log" => [],
      "node_outputs" => {},
      "edge_states" => { "edge-false" => "disabled" },
      "node_states" => {
        "n1" => { "status" => "disabled", "node_type" => "set_variable" },
      },
    }
  end

  def expect_disabled_debug_markup
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-edge-id="edge-false"')
    expect(response.body).to include('data-edge-state="disabled"')
    expect(response.body).to include('data-node-id="n1"')
    expect(response.body).to include('data-state="disabled"')
  end

  describe "GET /admin/missions" do
    it "returns ok" do
      get admin_missions_path
      expect(response).to have_http_status(:ok)
    end

    context "with operation scoping" do
      it "only shows missions belonging to the current operation" do
        operation = create(:operation)
        create(:mission, name: "Scoped Mission", operation:)
        create(:mission, name: "Other Mission", operation: create(:operation))
        post switch_admin_operation_path(operation), headers: { "HTTP_REFERER" => admin_missions_url }
        get admin_missions_path
        expect(response.body).to include("Scoped Mission")
        expect(response.body).not_to include("Other Mission")
      end
    end

    context "when unauthenticated", :unauthenticated do
      it "redirects to login" do
        get admin_missions_path
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "GET /admin/missions/new" do
    it "returns ok" do
      get new_admin_mission_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/missions" do
    it "creates a mission and redirects to the designer" do
      expect do
        post admin_missions_path, params: { mission: { name: "My New Mission", description: "Test" } }
      end.to change(Mission, :count).by(1)

      expect(response).to redirect_to(designer_admin_mission_path(Mission.last))
    end

    it "renders new when params are invalid" do
      post admin_missions_path, params: { mission: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /admin/missions/:id/edit" do
    it "returns ok" do
      get edit_admin_mission_path(mission)
      expect(response).to have_http_status(:ok)
    end

    it "does not show the clone action in the edit page header" do
      get edit_admin_mission_path(mission)

      expect(response.body).not_to include(clone_admin_mission_path(mission))
    end

    it "loads a mission from another operation in the same tenant and adopts its operation" do
      headquarter = default_tenant.headquarter_operation

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_missions_url }
      get edit_admin_mission_path(mission)

      expect(response).to have_http_status(:ok)
      expect(request.session[:current_operation_id]).to eq(mission.operation_id)
    end

    it "returns not found for a mission from another tenant" do
      other_tenant = create(:tenant)
      other_tenant.ensure_core_resources!
      other_mission = create(:mission, operation: other_tenant.default_operation)

      get edit_admin_mission_path(other_mission)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /admin/missions/:id" do
    it "updates the mission and redirects to index" do
      patch admin_mission_path(mission), params: { mission: { name: "Updated Name" } }
      expect(response).to redirect_to(admin_missions_path)
      expect(mission.reload.name).to eq("Updated Name")
    end

    it "renders edit on invalid params" do
      patch admin_mission_path(mission), params: { mission: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /admin/missions/:id" do
    it "destroys the mission and redirects" do
      expect do
        delete admin_mission_path(mission)
      end.to change(Mission, :count).by(-1)

      expect(response).to redirect_to(admin_missions_path)
    end

    it "does not delete a mission from another tenant" do
      other_tenant = create(:tenant)
      other_tenant.ensure_core_resources!
      other_mission = create(:mission, operation: other_tenant.default_operation)

      expect do
        delete admin_mission_path(other_mission)
      end.not_to change(Mission, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/missions/:id/clone" do
    before do
      mission.update!(
        flow_data: {
          "nodes" => [{ "id" => "n1", "type" => "input" }],
          "edges" => [],
          "global_variables" => [{ "key" => "region", "value" => "eu-west", "type" => "string" }],
        },
        flow_undo_history: [{ "nodes" => [{ "id" => "old" }], "edges" => [] }],
        flow_redo_history: [{ "nodes" => [{ "id" => "future" }], "edges" => [] }],
      )
    end

    it "clones the mission flow and redirects to the cloned designer" do
      expect do
        post clone_admin_mission_path(mission)
      end.to change(Mission, :count).by(1)

      clone = Mission.order(:id).last

      expect(response).to redirect_to(designer_admin_mission_path(clone))
      expect(flash[:notice]).to eq(I18n.t("missions.cloned"))
      expect(clone).to have_attributes(
        name: "Clone of #{mission.name}",
        description: mission.description,
        flow_data: mission.flow_data,
        flow_undo_history: [],
        flow_redo_history: [],
      )
    end

    it "redirects back to the original mission designer when the clone is invalid" do
      mission.update!(name: "M" * 247)

      expect do
        post clone_admin_mission_path(mission)
      end.not_to change(Mission, :count)

      expect(response).to redirect_to(designer_admin_mission_path(mission))
      expect(flash[:alert]).to include("Name is too long")
    end
  end

  describe "GET /admin/missions/:id/designer" do
    def activity_bar_descriptor(child)
      return "assistant" if child["data-sidebar-tab"] == "assistant"
      return "page-separator" if child["data-admin-sidebar-slot-separator"] == "page-tabs"
      return "tabs-before" if child["data-admin-sidebar-slot"] == "tabs-before-chat"
      return "tabs-after" if child["data-admin-sidebar-slot"] == "tabs-after-chat"
      return "collapse" if child["class"].to_s.include?("ms-sidebar-collapse-btn")
      return "separator" if child["class"].to_s.include?("ms-sidebar-activity-sep")

      nil
    end

    def activity_bar_descriptors(document)
      document.at_css(".admin-panel-sidebar .ms-sidebar-activity-bar").element_children.filter_map do |child|
        activity_bar_descriptor(child)
      end
    end

    it "returns ok and assigns llm_connectors" do
      get designer_admin_mission_path(mission)
      expect(response).to have_http_status(:ok)
    end

    it "renders the latest debug run when one exists" do
      run = create(:mission_run, mission:, status: "completed", started_at: 2.minutes.ago, completed_at: 1.minute.ago)

      get designer_admin_mission_path(mission)

      document = response.parsed_body
      past_run = document.at_css("#mission-past-run-#{run.id}")

      expect(past_run).to be_present
      expect(past_run.at_css(".ms-debug-past-run-status")&.text&.strip).to eq("Completed")
      expect(document.at_css("#mission-run-status")&.text).to include("Completed")
    end

    it "renders the designer with the shared compact page header and no actions" do
      get designer_admin_mission_path(mission)

      document = response.parsed_body
      hero = document.at_css(".page-hero__heading")

      expect(hero).to be_present
      expect(hero.at_css(".page-hero__title-badge")&.text).to include("Mission")
      expect(hero.at_css(".page-hero__record-title")&.text).to include(mission.name)
      expect(document.at_css(".page-hero__action-group")).to be_nil
      expect(document.at_css("#mission-designer-root")).to be_present
    end

    it "shows the clone action in the mission properties tab with confirmation" do
      get designer_admin_mission_path(mission)

      expect(response.body).to include(clone_admin_mission_path(mission))
      expect(response.body).to include("Clone Mission")
      expect(response.body).to include("data-confirm-title-value=\"Clone Mission\"")
    end

    it "renders mission tabs inside the shared admin sidebar shell", :aggregate_failures do
      get designer_admin_mission_path(mission)

      document = response.parsed_body
      node_properties_frame = document.at_css(
        ".main-content[data-controller~='mission'] " \
        "turbo-frame#node-properties[data-mission-target='nodePropertiesFrame']",
      )

      expect(document.at_css("[data-controller='panel-sidebar']")).to be_present
      expect(document.at_css(".main-content[data-controller~='mission']")).to be_present
      expect(node_properties_frame).to be_present
      expect(document.at_css("[data-sidebar-tab='assistant']")).to be_present
      expect(document.at_css("[data-sidebar-tab='components']")).to be_present
      expect(document.css(".ms-sidebar-panel-close")).to be_empty
    end

    it "renders the activity bar with assistant first and collapse last", :aggregate_failures do
      get designer_admin_mission_path(mission)

      document = response.parsed_body
      expect(activity_bar_descriptors(document)).to eq(
        [
          "assistant",
          "page-separator",
          "tabs-before",
          "tabs-after",
          "separator",
          "collapse",
        ],
      )
    end

    it "includes admin frame state for turbo frame navigation", :aggregate_failures do
      get designer_admin_mission_path(mission), headers: { "Turbo-Frame" => "app-content-frame" }

      document = response.parsed_body
      frame_state = document.at_css(".admin-frame-state[data-admin-frame-state]")

      expect(response).to have_http_status(:ok)
      expect(frame_state).to be_present
      expect(frame_state["data-admin-frame-state-main-content-data"]).to include('"controller":"mission"')
      expect(frame_state.to_html).to include('data-sidebar-tab="components"')
      expect(frame_state.to_html).to include('data-sidebar-tab="inspector"')
      expect(frame_state.to_html).to include('data-mission-target="nodePropertiesFrame"')
    end

    it "routes mission sidebar quick links through the content frame", :aggregate_failures do
      get designer_admin_mission_path(mission)

      document = response.parsed_body
      quick_links = document.css(".admin-panel-sidebar .ms-props-actions a.ms-props-btn")

      expect(quick_links.pluck("href")).to contain_exactly(
        admin_missions_path,
        admin_mission_mission_triggers_path(mission),
        edit_admin_mission_path(mission),
      )
      expect(quick_links.pluck("data-turbo-frame")).to all(eq("app-content-frame"))
    end

    it "keeps the assistant mount on the designer page" do
      get designer_admin_mission_path(mission)

      document = response.parsed_body

      expect(document.at_css("#admin-agent-alpha")).to be_present
    end
  end

  describe "GET /admin/missions/:id/flow_data_json" do
    it "returns flow data as JSON" do
      mission.update!(flow_data: { "nodes" => [{ "id" => "n1", "type" => "llm" }], "edges" => [] })
      get flow_data_json_admin_mission_path(mission), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["nodes"]).to be_an(Array)
      expect(body).to include("can_undo", "can_redo")
    end

    it "returns flow data when the session currently points to another operation" do
      headquarter = default_tenant.headquarter_operation

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_missions_url }
      get flow_data_json_admin_mission_path(mission), as: :json

      expect(response).to have_http_status(:ok)
      expect(request.session[:current_operation_id]).to eq(mission.operation_id)
    end

    it "backfills custom edge metadata for persisted edges" do
      mission.update!(flow_data: {
                        "nodes" => [
                          { "id" => "n1", "type" => "condition" },
                          { "id" => "n2", "type" => "llm" },
                        ],
                        "edges" => [
                          { "id" => "e1", "source" => "n1", "sourceHandle" => "false", "target" => "n2" },
                        ],
                      })

      get flow_data_json_admin_mission_path(mission), as: :json

      edge = response.parsed_body.fetch("edges").first
      expect(edge["type"]).to eq("custom")
      expect(edge.dig("markerEnd", "type")).to eq("arrowclosed")
      expect(edge.dig("data", "label")).to eq("false")
    end
  end

  describe "PATCH /admin/missions/:id/save_flow" do
    let(:flow_payload) { { "nodes" => [{ "id" => "n1", "type" => "input" }], "edges" => [] } }
    let(:normalized_flow_payload) do
      {
        "nodes" => [{ "id" => "n1", "type" => "input", "position" => { "x" => 0, "y" => 0 } }],
        "edges" => [],
      }
    end
    let(:llm_flow_payload) do
      {
        "nodes" => [{
          "id" => "n1",
          "type" => "llm",
          "data" => {
            "label" => "Draft Reply",
            "prompt" => "Hello",
            "thinking_effort" => "high",
            "thinking_budget" => "256",
          },
        }],
        "edges" => [],
      }
    end

    it "saves the flow and redirects (HTML)" do
      patch save_flow_admin_mission_path(mission), params: { mission: { flow_data: flow_payload.to_json } }
      expect(response).to redirect_to(admin_missions_path)
      expect(mission.reload.flow_data).to eq(normalized_flow_payload)
    end

    it "returns saved: true (JSON)" do
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: flow_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["saved"]).to be(true)
      expect(response.parsed_body).to include("can_undo", "can_redo")
    end

    it "defaults an llm node with omitted connection settings to system preference" do
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: llm_flow_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(mission.reload.flow_data.dig("nodes", 0, "data")).to include(
        "llm_config_source" => "system_preference",
        "thinking_effort" => "high",
        "thinking_budget" => 256,
      )
    end

    it "normalizes edge rendering metadata before saving" do
      payload = {
        "nodes" => [
          { "id" => "n1", "type" => "condition" },
          { "id" => "n2", "type" => "llm" },
        ],
        "edges" => [
          { "id" => "e1", "source" => "n1", "sourceHandle" => "false", "target" => "n2" },
        ],
      }

      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: payload.to_json } },
            as: :json

      edge = mission.reload.flow_data.fetch("edges").first
      expect(edge["type"]).to eq("custom")
      expect(edge.dig("markerEnd", "type")).to eq("arrowclosed")
      expect(edge.dig("data", "label")).to eq("false")
    end

    it "returns errors on invalid data (JSON)" do
      allow_any_instance_of(Mission).to receive(:update).and_return(false) # rubocop:disable RSpec/AnyInstance
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: flow_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["saved"]).to be(false)
    end

    it "skips undo snapshot when flow_data is unchanged" do
      mission.update!(flow_data: flow_payload)
      expect_any_instance_of(Mission).not_to receive(:push_undo_snapshot!) # rubocop:disable RSpec/AnyInstance
      patch save_flow_admin_mission_path(mission), params: { mission: { flow_data: flow_payload.to_json } }
      expect(response).to redirect_to(admin_missions_path)
    end

    it "ignores transient selection fields when saving flow" do
      mission.update!(flow_data: flow_payload)

      transient_payload = {
        "nodes" => [{ "id" => "n1", "type" => "input", "selected" => true, "dragging" => false }],
        "edges" => [],
      }

      expect_any_instance_of(Mission).not_to receive(:push_undo_snapshot!) # rubocop:disable RSpec/AnyInstance
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: transient_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["saved"]).to be(true)
      expect(mission.reload.flow_data).to eq(normalized_flow_payload)
    end

    it "saves an empty flow when flow_data is invalid JSON" do
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: "not valid json!!" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["saved"]).to be(true)
      expect(mission.reload.flow_data).to eq({ "nodes" => [], "edges" => [] })
    end

    it "saves an empty flow when flow_data is blank" do
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: "" } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["saved"]).to be(true)
      expect(mission.reload.flow_data).to eq({ "nodes" => [], "edges" => [] })
    end

    it "coerces numeric node data before saving" do
      payload = {
        "nodes" => [{
          "id" => "n1",
          "type" => "llm",
          "data" => {
            "temperature" => "0.8",
            "count" => "3",
            "thinking_budget" => "128",
          },
        }],
        "edges" => [],
      }

      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: payload.to_json } },
            as: :json

      data = mission.reload.flow_data.dig("nodes", 0, "data")
      expect(data["temperature"]).to eq(0.8)
      expect(data["count"]).to eq(3)
      expect(data["thinking_budget"]).to eq(128)
    end

    it "coerces llm tool_ids arrays to integers before saving" do
      payload = {
        "nodes" => [{
          "id" => "n1",
          "type" => "llm",
          "data" => {
            "tool_ids" => ["4", "bad", 9],
          },
        }],
        "edges" => [],
      }

      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: payload.to_json } },
            as: :json

      data = mission.reload.flow_data.dig("nodes", 0, "data")
      expect(data["tool_ids"]).to eq([4, 9])
    end

    it "persists global_variables in flow_data and returns them in the response" do
      gv_payload = {
        "nodes" => [{ "id" => "n1", "type" => "input" }],
        "edges" => [],
        "global_variables" => [{ "key" => "api_key", "value" => "secret", "type" => "string" }],
      }
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: gv_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["global_variables"]).to eq([{ "key" => "api_key", "value" => "secret", "type" => "string" }])
      expect(mission.reload.flow_data["global_variables"]).to eq(gv_payload["global_variables"])
    end

    it "strips global_variables when saved with an empty array" do
      mission.update!(flow_data: {
                        "nodes" => [], "edges" => [],
                        "global_variables" => [{ "key" => "old", "value" => "val", "type" => "string" }],
                      })
      empty_gv_payload = { "nodes" => [], "edges" => [], "global_variables" => [] }
      patch save_flow_admin_mission_path(mission),
            params: { mission: { flow_data: empty_gv_payload.to_json } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(mission.reload.flow_data.key?("global_variables")).to be(false)
    end

    it "does not save flows for Headquarter missions" do
      headquarter = default_tenant.headquarter_operation
      headquarter_mission = create(:mission, operation: headquarter)
      previous_flow = headquarter_mission.flow_data.deep_dup

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_missions_url }
      patch save_flow_admin_mission_path(headquarter_mission),
            params: { mission: { flow_data: flow_payload.to_json } },
            headers: { "HTTP_REFERER" => designer_admin_mission_path(headquarter_mission) }

      expect(response).to redirect_to(designer_admin_mission_path(headquarter_mission))
      expect(headquarter_mission.reload.flow_data).to eq(previous_flow)
    end
  end

  describe "GET /admin/missions/:id/debug_inputs" do
    it "returns the debug inputs partial" do
      mission.update!(flow_data: {
                        "nodes" => [{
                          "id" => "n1",
                          "type" => "input",
                          "data" => {
                            "fields" => [
                              { "variable_name" => "name", "field_type" => "string", "label" => "Name" },
                            ],
                          },
                        }],
                        "edges" => [],
                      })
      get debug_inputs_admin_mission_path(mission)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name")
    end

    it "returns debug inputs when the session currently points to another operation" do
      headquarter = default_tenant.headquarter_operation

      post switch_admin_operation_path(headquarter), headers: { "HTTP_REFERER" => admin_missions_url }
      get debug_inputs_admin_mission_path(mission)

      expect(response).to have_http_status(:ok)
      expect(request.session[:current_operation_id]).to eq(mission.operation_id)
    end
  end

  describe "POST /admin/missions/:id/execute_debug" do
    before { allow(MissionExecutionJob).to receive(:perform_later) }

    it "creates a pending MissionRun and enqueues the job (JSON)" do
      expect do
        post execute_debug_admin_mission_path(mission), as: :json
      end.to change(MissionRun, :count).by(1)

      expect(MissionExecutionJob).to have_received(:perform_later)
      run = MissionRun.last
      expect(run.status).to eq("pending")
      json = response.parsed_body
      expect(json["run_id"]).to eq(run.id)
      expect(json["status"]).to eq("pending")
    end

    it "accepts optional variables and trigger_data params (JSON)" do
      post execute_debug_admin_mission_path(mission),
           params: { variables: { "x" => 1 }.to_json, trigger_data: { "event" => "test" }.to_json },
           as: :json

      expect(MissionExecutionJob).to have_received(:perform_later).with(
        anything,
        tenant_id: mission.operation.tenant_id,
        variables: { "x" => 1 },
        trigger_data: { "event" => "test" },
      )
    end

    it "falls back to empty hash when variables param is not valid JSON" do
      post execute_debug_admin_mission_path(mission),
           params: { variables: "not valid json!!" },
           as: :json

      expect(MissionExecutionJob).to have_received(:perform_later).with(
        anything,
        tenant_id: mission.operation.tenant_id,
        variables: {},
        trigger_data: {},
      )
    end

    it "updates flow_data when flow_data param is present (JSON)" do
      new_flow = { "nodes" => [], "edges" => [] }
      post execute_debug_admin_mission_path(mission),
           params: { flow_data: new_flow.to_json },
           as: :json

      expect(mission.reload.flow_data).to eq(new_flow)
    end

    it "attaches uploaded files and injects blob info into trigger_data" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new("file content"),
        "text/plain",
        true,
        original_filename: "test_upload.txt",
      )

      post execute_debug_admin_mission_path(mission),
           params: {
             trigger_data: { "query" => "hello" }.to_json,
             trigger_files: { "document" => [file] },
           }

      run = MissionRun.last
      expect(run.files).to be_attached

      expect(MissionExecutionJob).to have_received(:perform_later) do |_run_id, **kwargs|
        doc = kwargs[:trigger_data]["document"]
        expect(doc).to be_a(Hash)
        expect(doc[:filename]).to eq("test_upload.txt")
        expect(doc[:blob_id]).to be_present
      end
    end

    it "returns an array when multiple files are uploaded for one field" do
      files = Array.new(2) do |i|
        Rack::Test::UploadedFile.new(
          StringIO.new("content #{i}"),
          "text/plain",
          true,
          original_filename: "file_#{i}.txt",
        )
      end

      post execute_debug_admin_mission_path(mission),
           params: {
             trigger_data: {}.to_json,
             trigger_files: { "docs" => files },
           }

      expect(MissionExecutionJob).to have_received(:perform_later) do |_run_id, **kwargs|
        docs = kwargs[:trigger_data]["docs"]
        expect(docs).to be_an(Array)
        expect(docs.size).to eq(2)
      end
    end

    it "handles execute_debug without file uploads" do
      post execute_debug_admin_mission_path(mission),
           params: { trigger_data: { "name" => "test" }.to_json },
           as: :json

      expect(MissionExecutionJob).to have_received(:perform_later).with(
        anything,
        tenant_id: mission.operation.tenant_id,
        variables: {},
        trigger_data: { "name" => "test" },
      )
    end

    it "ignores trigger file entries that are not uploaded files" do
      post execute_debug_admin_mission_path(mission),
           params: {
             trigger_data: { "name" => "test" }.to_json,
             trigger_files: { "document" => ["not-a-file"] },
           },
           as: :json

      expect(MissionExecutionJob).to have_received(:perform_later).with(
        anything,
        tenant_id: mission.operation.tenant_id,
        variables: {},
        trigger_data: { "name" => "test" },
      )
    end

    context "with a mission that has input fields" do
      let(:mission_with_inputs) do
        create(:mission, name: "Input Mission", flow_data: {
                 "nodes" => [{
                   "id" => "1",
                   "type" => "input",
                   "data" => {
                     "fields" => [
                       { "variable_name" => "query", "field_type" => "string", "required" => true },
                     ],
                   },
                 }],
                 "edges" => [],
               },)
      end

      it "filters trigger_data to only defined input fields" do
        post execute_debug_admin_mission_path(mission_with_inputs),
             params: { trigger_data: { "query" => "hello", "extra" => "removed" }.to_json },
             as: :json

        expect(MissionExecutionJob).to have_received(:perform_later).with(
          anything,
          tenant_id: mission_with_inputs.operation.tenant_id,
          variables: {},
          trigger_data: { "query" => "hello" },
        )
      end
    end
  end

  describe "GET /admin/missions/:id/run_status" do
    it "returns status: none when there are no runs" do
      get run_status_admin_mission_path(mission), as: :json
      expect(response.parsed_body["status"]).to eq("none")
    end

    it "returns serialized run data when a run exists" do
      run = create(:mission_run, mission:, status: "completed",
                                 started_at: 10.seconds.ago, completed_at: Time.current,)
      get run_status_admin_mission_path(mission), as: :json

      body = response.parsed_body
      expect(body["run_id"]).to eq(run.id)
      expect(body["status"]).to eq("completed")
    end

    it "serializes nil timestamps and duration for a pending run" do
      create(:mission_run, mission:, status: "pending")
      get run_status_admin_mission_path(mission), as: :json

      body = response.parsed_body
      expect(body["status"]).to eq("pending")
      expect(body["started_at"]).to be_nil
      expect(body["completed_at"]).to be_nil
      expect(body["duration_ms"]).to be_nil
    end

    it "serializes runs where execution_state has no log keys" do
      # execution_state: {} means dig returns nil → || fallback branches in serialize_run covered
      create(:mission_run, mission:, status: "failed")
      get run_status_admin_mission_path(mission), as: :json

      body = response.parsed_body
      expect(body["status"]).to eq("failed")
      expect(body["execution_log"]).to eq([])
      expect(body["node_outputs"]).to eq({})
    end

    it "computes duration_ms from started_at/finished_at in execution_log entries" do
      started = 2.seconds.ago
      finished = started + 0.5
      log_entry = {
        "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
        "started_at" => started.iso8601(3), "finished_at" => finished.iso8601(3),
        "output" => nil, "next_port" => "default", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_status_admin_mission_path(mission), as: :json

      body = response.parsed_body
      entry = body["execution_log"].first
      expect(entry["duration_ms"]).to be_a(Numeric)
      expect(entry["duration_ms"]).to be > 0
    end

    it "skips duration_ms when timestamps are missing from execution_log entries" do
      log_entry = {
        "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
        "started_at" => nil, "finished_at" => nil,
        "output" => nil, "next_port" => "default", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_status_admin_mission_path(mission), as: :json

      body = response.parsed_body
      entry = body["execution_log"].first
      expect(entry["duration_ms"]).to be_nil
    end
  end

  describe "POST /admin/missions/:id/cancel_run" do
    it "cancels the active run and returns status: cancelled (JSON)" do
      run = create(:mission_run, mission:, status: "running",
                                 flow_snapshot: mission.flow_data,)
      post cancel_run_admin_mission_path(mission), as: :json

      expect(response.parsed_body["status"]).to eq("cancelled")
      expect(run.reload).to be_cancelled
    end

    it "cancels the active run and returns turbo_stream replacements" do
      create(:mission_run, mission:, status: "running", flow_snapshot: mission.flow_data)
      post cancel_run_admin_mission_path(mission),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
    end

    it "returns status: none when there is no active run (JSON)" do
      post cancel_run_admin_mission_path(mission), as: :json
      expect(response.parsed_body["status"]).to eq("none")
    end
  end

  describe "GET /admin/missions/:id/run_catch_up" do
    it "returns no_content when there is no run" do
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:no_content)
    end

    it "renders a turbo stream response with run state when a run exists" do
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: { "x" => 1 },
                           execution_state: { "execution_log" => [], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-stream")
    end

    it "renders correctly when execution_state has no log keys and duration is nil" do
      # execution_state: {} means dig returns nil → || fallback branches are covered
      # no started_at → run.duration is nil → ternary else branch covered
      create(:mission_run, mission:, status: "running")
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
    end

    it "enriches execution_log entries with node_label from flow_data" do
      mission.update!(flow_data: {
                        "nodes" => [{ "id" => "n1", "type" => "set_variable",
                                      "data" => { "label" => "Set API Key" }, }],
                        "edges" => [],
                      })
      log_entry = {
        "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
        "started_at" => 2.seconds.ago.iso8601(3), "finished_at" => 1.second.ago.iso8601(3),
        "output" => "done", "next_port" => "default", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Set API Key")
    end

    it "preserves node_label already present in execution_log" do
      log_entry = {
        "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
        "node_label" => "Pre-set Label",
        "started_at" => 2.seconds.ago.iso8601(3), "finished_at" => 1.second.ago.iso8601(3),
        "output" => "done", "next_port" => "default", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pre-set Label")
    end

    it "enriches execution_log entries with computed duration_ms" do
      started = 2.seconds.ago
      finished = started + 0.25
      log_entry = {
        "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
        "started_at" => started.iso8601(3), "finished_at" => finished.iso8601(3),
        "output" => "done", "next_port" => "default", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: { "x" => 1 },
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("set_variable")
      expect(response.body).to include("ms")
    end

    it "renders execution inputs in timeline entries" do
      log_entry = {
        "node_id" => "n1", "node_type" => "http_request", "status" => "success",
        "input" => { "url" => "https://api.example.com/users" },
        "started_at" => 2.seconds.ago.iso8601(3), "finished_at" => 1.second.ago.iso8601(3),
        "output" => "ok", "next_port" => "success", "error" => nil,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)

      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Input")
      expect(response.body).to include("https://api.example.com/users")
    end

    it "emits completed-count for iterator done entries using output array length" do
      log_entry = {
        "node_id" => "iter1", "node_type" => "iterator", "status" => "success",
        "next_port" => "done", "output" => ["a", "b", "c"],
        "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 50,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => [log_entry], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-completed-count="3"')
    end

    it "falls back to count increment when iterator done output is not an array" do
      # A non-success entry should be skipped; the success entry is counted once
      running_entry = {
        "node_id" => "iter1", "node_type" => "iterator", "status" => "running",
        "next_port" => nil, "output" => nil,
        "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => nil,
      }
      log_entry = {
        "node_id" => "iter1", "node_type" => "iterator", "status" => "success",
        "next_port" => "done", "output" => "scalar",
        "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 50,
      }
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => [running_entry, log_entry], "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-completed-count="1"')
    end

    it "does not count loop done entries as extra loop executions" do # rubocop:disable RSpec/ExampleLength
      log_entries = [
        {
          "node_id" => "loop1", "node_type" => "loop", "status" => "success",
          "next_port" => "loop", "output" => 0,
          "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 10,
        },
        {
          "node_id" => "loop1", "node_type" => "loop", "status" => "success",
          "next_port" => "loop", "output" => 1,
          "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 10,
        },
        {
          "node_id" => "loop1", "node_type" => "loop", "status" => "success",
          "next_port" => "loop", "output" => 2,
          "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 10,
        },
        {
          "node_id" => "loop1", "node_type" => "loop", "status" => "success",
          "next_port" => "done", "output" => { "counter" => 9 },
          "started_at" => nil, "finished_at" => nil, "error" => nil, "duration_ms" => 10,
        },
      ]
      create(:mission_run, mission:, status: "completed",
                           started_at: 10.seconds.ago, completed_at: Time.current,
                           variables: {},
                           execution_state: { "execution_log" => log_entries, "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-completed-count="3"')
      expect(response.body).not_to include('data-completed-count="4"')
    end

    it "renders timeline entries for an actively running mission (mid-execution catch-up)" do
      log_entries = [
        { "node_id" => "n1", "node_type" => "set_variable", "status" => "success",
          "started_at" => 3.seconds.ago.iso8601(3), "finished_at" => 2.seconds.ago.iso8601(3),
          "output" => "step1", "next_port" => "default", "error" => nil, },
        { "node_id" => "n2", "node_type" => "llm", "status" => "success",
          "started_at" => 2.seconds.ago.iso8601(3), "finished_at" => 1.second.ago.iso8601(3),
          "output" => "step2", "next_port" => "default", "error" => nil, },
      ]
      create(:mission_run, mission:, status: "running",
                           started_at: 5.seconds.ago,
                           variables: { "x" => 1 },
                           execution_state: { "execution_log" => log_entries, "node_outputs" => {} },)
      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("mission-timeline-entries")
      expect(response.body).to include("set_variable")
      expect(response.body).to include("llm")
    end

    it "replays disabled edge and node states from execution_state" do
      mission.update!(flow_data: disabled_debug_flow)
      create(:mission_run, mission:, status: "running",
                           execution_state: disabled_debug_execution_state,)

      get run_catch_up_admin_mission_path(mission),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect_disabled_debug_markup
    end
  end

  describe "GET /admin/missions/:id/node_model_options" do
    let(:llm_connector) { create(:connector, :llm_provider, name: "OpenAI") }

    it "returns a Turbo Frame with an empty select when connector_id is blank" do
      get node_model_options_admin_mission_path(mission)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame")
      expect(response.body).to include("node-model-select")
    end

    it "includes model capability metadata on model options" do
      create(:model, provider: llm_connector.provider, model_id: "gpt-4.1",
                     capabilities: ["temperature", "reasoning"],)

      get node_model_options_admin_mission_path(mission), params: { connector_id: llm_connector.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-custom-properties")
      expect(response.body).to include("supports_reasoning")
      expect(response.body).to include("supports_temperature")
    end
  end

  describe "GET /admin/missions/:id/node_image_model_options" do
    it "returns a Turbo Frame filtering image models" do
      connector = create(:connector, :llm_provider, name: "ImageAI")
      get node_image_model_options_admin_mission_path(mission), params: { connector_id: connector.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame")
      expect(response.body).to include("node-model-select")
    end
  end

  describe "GET /admin/missions/:id/mission_io_fields" do
    let(:input_fields) do
      [{ "variable_name" => "query", "field_type" => "string", "required" => true, "label" => "Query" }]
    end
    let(:sub_flow) do
      {
        "nodes" => [
          { "type" => "input", "id" => "n1",
            "data" => { "fields" => input_fields }, },
          { "type" => "output", "id" => "n2",
            "data" => { "selected_variables" => ["summarize.response"] }, },
        ],
        "edges" => [],
      }
    end
    let(:sub_mission) { create(:mission, flow_data: sub_flow) }

    it "returns input and output fields for the given sub-mission" do
      get mission_io_fields_admin_mission_path(mission), params: { sub_mission_id: sub_mission.id }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["input_fields"].first["variable_name"]).to eq("query")
      expect(body["input_fields"].first["field_type"]).to eq("string")
      expect(body["input_fields"].first["required"]).to be(true)
      expect(body["output_fields"].first["variable_name"]).to eq("summarize.response")
    end

    it "returns empty arrays when sub_mission_id is not found" do
      get mission_io_fields_admin_mission_path(mission), params: { sub_mission_id: "nonexistent" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["input_fields"]).to eq([])
      expect(body["output_fields"]).to eq([])
    end

    it "returns empty input fields when mission has no input node" do
      no_input_mission = create(:mission, flow_data: { "nodes" => [], "edges" => [] })

      get mission_io_fields_admin_mission_path(mission), params: { sub_mission_id: no_input_mission.id }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["input_fields"]).to eq([])
      expect(body["output_fields"]).to eq([])
    end

    it "skips fields with blank variable_name" do
      blank_field_flow = {
        "nodes" => [{ "type" => "input", "id" => "n1",
                      "data" => { "fields" => [{ "variable_name" => "", "field_type" => "string" }] }, }],
        "edges" => [],
      }
      blank_mission = create(:mission, flow_data: blank_field_flow)

      get mission_io_fields_admin_mission_path(mission), params: { sub_mission_id: blank_mission.id }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["input_fields"]).to eq([])
    end
  end

  describe "POST /admin/missions/:id/duplicate_node" do
    let(:original_node) do
      { "id" => "node-1", "type" => "llm", "position" => { "x" => 100, "y" => 200 }, "data" => { "label" => "LLM" } }
    end
    let(:mission_with_node) do
      create(:mission, flow_data: { "nodes" => [original_node], "edges" => [] })
    end

    it "returns a new node with an offset position and persists the change" do
      post duplicate_node_admin_mission_path(mission_with_node),
           params: { node_id: "node-1", flow_data: mission_with_node.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["nodes"].length).to eq(2)
      duplicate = body["nodes"].find { |n| n["id"] != "node-1" }
      expect(duplicate["type"]).to eq("llm")
      expect(duplicate["position"]).to eq({ "x" => 132.0, "y" => 232.0 })
      expect(mission_with_node.reload.flow_data["nodes"].length).to eq(2)
    end

    it "returns 404 when node_id is not found in flow_data" do
      post duplicate_node_admin_mission_path(mission_with_node),
           params: { node_id: "nonexistent", flow_data: mission_with_node.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to match(/not found/i)
    end

    it "falls back to empty flow when flow_data is invalid JSON" do
      post duplicate_node_admin_mission_path(mission),
           params: { node_id: "node-1", flow_data: "not valid JSON!!" },
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "initialises missing 'nodes'/'edges' keys when flow_data omits them" do
      post duplicate_node_admin_mission_path(mission),
           params: { node_id: "absent", flow_data: { other: "data" }.to_json },
           as: :json

      # parse_flow_param fills in missing keys; node still not found
      expect(response).to have_http_status(:not_found)
    end

    it "rejects duplicating a singleton node type" do
      input_node = { "id" => "node-1", "type" => "input", "position" => { "x" => 0, "y" => 0 }, "data" => {} }
      m = create(:mission, flow_data: { "nodes" => [input_node], "edges" => [] })

      post duplicate_node_admin_mission_path(m),
           params: { node_id: "node-1", flow_data: m.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/only one input/i)
    end
  end

  describe "POST /admin/missions/:id/delete_node" do
    let(:node_a) { { "id" => "node-a", "type" => "llm", "position" => { "x" => 0, "y" => 0 }, "data" => {} } }
    let(:node_b) { { "id" => "node-b", "type" => "agent", "position" => { "x" => 0, "y" => 0 }, "data" => {} } }
    let(:edge)   { { "id" => "e1", "source" => "node-a", "target" => "node-b" } }
    let(:mission_with_nodes) do
      create(:mission, flow_data: { "nodes" => [node_a, node_b], "edges" => [edge] })
    end

    it "removes the node and all connected edges, persists the change" do
      post delete_node_admin_mission_path(mission_with_nodes),
           params: { node_id: "node-a", flow_data: mission_with_nodes.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["nodes"].pluck("id")).to eq(["node-b"])
      expect(body["edges"]).to be_empty
      expect(mission_with_nodes.reload.flow_data["nodes"].length).to eq(1)
      expect(mission_with_nodes.reload.flow_data["edges"]).to be_empty
    end

    it "removes nodes where the target matches the deleted node_id" do
      # Covers the right-hand side of `e["source"] == node_id || e["target"] == node_id`
      post delete_node_admin_mission_path(mission_with_nodes),
           params: { node_id: "node-b", flow_data: mission_with_nodes.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["nodes"].pluck("id")).to eq(["node-a"])
      expect(body["edges"]).to be_empty
    end

    it "is a no-op when node_id does not exist in flow_data" do
      post delete_node_admin_mission_path(mission_with_nodes),
           params: { node_id: "nonexistent", flow_data: mission_with_nodes.flow_data.to_json },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["nodes"].length).to eq(2)
    end

    it "falls back to empty flow when flow_data is invalid JSON" do
      post delete_node_admin_mission_path(mission),
           params: { node_id: "node-a", flow_data: "bad json" },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["nodes"]).to be_empty
    end

    it "falls back to empty flow when flow_data is blank" do
      post delete_node_admin_mission_path(mission),
           params: { node_id: "node-a" },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["nodes"]).to be_empty
    end
  end

  describe "POST /admin/missions/:id/undo_flow" do
    context "when undo history is empty" do
      it "returns current flow with can_undo: false and can_redo: false" do
        post undo_flow_admin_mission_path(mission), as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["can_undo"]).to be(false)
        expect(body["can_redo"]).to be(false)
        expect(body["nodes"]).to be_an(Array)
        expect(body["global_variables"]).to eq([])
      end
    end

    context "when undo history has a snapshot" do
      let(:old_node) { { "id" => "n-old", "type" => "llm", "position" => { "x" => 0, "y" => 0 }, "data" => {} } }
      let(:new_node) { { "id" => "n-new", "type" => "agent", "position" => { "x" => 100, "y" => 0 }, "data" => {} } }
      let(:old_flow) { { "nodes" => [old_node], "edges" => [] } }
      let(:current_flow) { { "nodes" => [old_node, new_node], "edges" => [] } }
      let(:mission_with_history) { create(:mission, flow_data: current_flow, flow_undo_history: [old_flow]) }

      it "returns the restored snapshot with correct can_undo/can_redo flags" do
        post undo_flow_admin_mission_path(mission_with_history), as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["nodes"].pluck("id")).to eq(["n-old"])
        expect(body["can_undo"]).to be(false)
        expect(body["can_redo"]).to be(true)
      end

      it "pops undo stack and pushes current flow onto redo stack" do
        post undo_flow_admin_mission_path(mission_with_history), as: :json

        mission_with_history.reload
        expect(mission_with_history.flow_undo_history).to be_empty
        expect(mission_with_history.flow_redo_history.length).to eq(1)
      end

      it "returns global_variables from the restored snapshot" do
        old_flow_with_gv = old_flow.merge(
          "global_variables" => [{ "key" => "env", "value" => "prod", "type" => "string" }],
        )
        mission_gv = create(:mission, flow_data: current_flow,
                                      flow_undo_history: [old_flow_with_gv],)
        post undo_flow_admin_mission_path(mission_gv), as: :json

        body = response.parsed_body
        expect(body["global_variables"]).to eq([{ "key" => "env", "value" => "prod", "type" => "string" }])
      end
    end
  end

  describe "POST /admin/missions/:id/redo_flow" do
    context "when redo history is empty" do
      it "returns current flow with can_undo: false and can_redo: false" do
        post redo_flow_admin_mission_path(mission), as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["can_redo"]).to be(false)
        expect(body["can_undo"]).to be(false)
      end
    end

    context "when redo history has a snapshot" do
      let(:node_a) { { "id" => "n-a", "type" => "llm", "position" => { "x" => 0, "y" => 0 }, "data" => {} } }
      let(:node_b) { { "id" => "n-b", "type" => "agent", "position" => { "x" => 100, "y" => 0 }, "data" => {} } }
      let(:future_flow) { { "nodes" => [node_a, node_b], "edges" => [] } }
      let(:current_flow) { { "nodes" => [node_a], "edges" => [] } }
      let(:mission_with_redo) { create(:mission, flow_data: current_flow, flow_redo_history: [future_flow]) }

      it "returns the restored snapshot with correct can_redo/can_undo flags" do
        post redo_flow_admin_mission_path(mission_with_redo), as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["nodes"].pluck("id")).to contain_exactly("n-a", "n-b")
        expect(body["can_redo"]).to be(false)
        expect(body["can_undo"]).to be(true)
      end

      it "pops redo stack and pushes current flow onto undo stack" do
        post redo_flow_admin_mission_path(mission_with_redo), as: :json

        mission_with_redo.reload
        expect(mission_with_redo.flow_redo_history).to be_empty
        expect(mission_with_redo.flow_undo_history.length).to eq(1)
      end

      it "returns global_variables from the restored snapshot" do
        future_flow_with_gv = future_flow.merge(
          "global_variables" => [{ "key" => "mode", "value" => "debug", "type" => "string" }],
        )
        mission_gv = create(:mission, flow_data: current_flow,
                                      flow_redo_history: [future_flow_with_gv],)
        post redo_flow_admin_mission_path(mission_gv), as: :json

        body = response.parsed_body
        expect(body["global_variables"]).to eq([{ "key" => "mode", "value" => "debug", "type" => "string" }])
      end
    end
  end

  describe "GET /admin/missions/:id/node_properties" do
    let(:llm_flow) do
      {
        "nodes" => [{ "id" => "n1", "type" => "llm",
                      "data" => { "label" => "My LLM", "prompt" => "Hello", "connector_id" => "1" }, }],
        "edges" => [],
      }
    end

    before { mission.update!(flow_data: llm_flow) }

    it "returns ok with a valid node_id" do
      get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My LLM")
    end

    it "returns not_found for a missing node_id" do
      get node_properties_admin_mission_path(mission), params: { node_id: "missing" }
      expect(response).to have_http_status(:not_found)
    end

    it "renders the turbo frame wrapper" do
      get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
      expect(response.body).to include("node-properties")
    end

    it "embeds the rendered node id in the properties payload" do
      get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
      expect(response.body).to include('data-property-node-id="n1"')
    end

    it "renders configuration section for the node type" do
      get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
      expect(response.body).to include("Configuration")
    end

    context "with a condition node" do
      let(:condition_flow) do
        {
          "nodes" => [{ "id" => "n1", "type" => "condition",
                        "data" => { "label" => "Check", "expression" => "x > 1" }, }],
          "edges" => [],
        }
      end

      before { mission.update!(flow_data: condition_flow) }

      it "renders the expression field" do
        get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
        expect(response.body).to include("x &gt; 1")
      end
    end

    context "with a set_variable node" do
      let(:set_var_flow) do
        {
          "nodes" => [{ "id" => "n1", "type" => "set_variable",
                        "data" => { "label" => "Set", "assignments" => { "foo" => "bar" } }, }],
          "edges" => [],
        }
      end

      before { mission.update!(flow_data: set_var_flow) }

      it "renders pre-populated assignment rows" do
        get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
        expect(response.body).to include("foo")
        expect(response.body).to include("bar")
      end
    end

    context "when unauthenticated", :unauthenticated do
      it "redirects to login" do
        get node_properties_admin_mission_path(mission), params: { node_id: "n1" }
        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "GET /admin/missions/:id/load_debug_run" do
    it "loads a specific run state as turbo stream" do
      run = create(:mission_run, mission:, status: "completed",
                                 flow_snapshot: mission.flow_data,
                                 execution_state: { "execution_log" => [], "node_outputs" => {}, "edge_states" => {} },)

      get load_debug_run_admin_mission_path(mission),
          params: { run_id: run.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("mission-timeline-content")
      expect(response.body).to include("mission-past-runs")
    end

    it "loads execution log entries" do
      log_entry = { "node_id" => "n1", "node_type" => "llm", "status" => "success",
                    "started_at" => Time.current.iso8601, "finished_at" => Time.current.iso8601, }
      run = create(:mission_run, mission:, status: "completed",
                                 flow_snapshot: mission.flow_data,
                                 execution_state: { "execution_log" => [log_entry], "node_outputs" => {},
                                                    "edge_states" => {}, },)

      get load_debug_run_admin_mission_path(mission),
          params: { run_id: run.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("mission-timeline-entries")
    end

    it "filters variables by global variable keys" do
      mission.update!(flow_data: mission.flow_data.merge("global_variables" => [{ "key" => "api_key" }]))
      run = create(:mission_run, mission:, status: "completed",
                                 flow_snapshot: mission.flow_data,
                                 variables: { "api_key" => "secret", "internal" => "hidden" },
                                 execution_state: { "execution_log" => [], "node_outputs" => {},
                                                    "edge_states" => {}, },)

      get load_debug_run_admin_mission_path(mission),
          params: { run_id: run.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("api_key")
    end

    it "loads disabled edge and node states for a past run" do
      mission.update!(flow_data: disabled_debug_flow)
      run = create(:mission_run, mission:, status: "completed",
                                 flow_snapshot: mission.flow_data,
                                 execution_state: disabled_debug_execution_state,)

      get load_debug_run_admin_mission_path(mission),
          params: { run_id: run.id },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect_disabled_debug_markup
    end
  end

  describe "POST /admin/missions/:id/reset_debug" do
    it "resets debug state and returns turbo stream" do
      create(:mission_run, mission:, status: "completed", flow_snapshot: mission.flow_data)

      post reset_debug_admin_mission_path(mission),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("mission-timeline-content")
      expect(response.body).to include("mission-past-runs")
      expect(response.body).to include("mission-run-controls")
    end

    it "returns empty past runs when none exist" do
      post reset_debug_admin_mission_path(mission),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No past executions yet")
    end
  end
end
