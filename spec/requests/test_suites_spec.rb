# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TestSuites" do
  let(:agent) { create(:agent) }

  describe "GET /test_suites" do
    it "returns a successful response" do
      get admin_test_suites_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "nested routes" do
    describe "GET /test_suites" do
      it "returns a successful response" do
        get admin_test_suites_path
        expect(response).to have_http_status(:ok)
      end

      it "lists test suites" do
        suite = create(:test_suite, agent:)
        get admin_test_suites_path
        expect(response.body).to include(suite.name)
      end

      it "shows empty state when no test suites exist" do
        get admin_test_suites_path
        expect(response.body).to include("No test suites yet")
      end
    end

    describe "GET /test_suites/:id" do
      let(:suite) { create(:test_suite, agent:) }

      it "returns a successful response" do
        get admin_test_suite_path(suite)
        expect(response).to have_http_status(:ok)
      end

      it "shows test suite details" do
        get admin_test_suite_path(suite)
        expect(response.body).to include(suite.name)
      end
    end

    describe "GET /test_suites/new" do
      it "returns a successful response" do
        get new_admin_test_suite_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /test_suites" do
      let(:valid_params) do
        { test_suite: { name: "New Suite", description: "Test description", suite_type: "agent", agent_id: agent.id } }
      end

      it "creates a new test suite with valid params" do
        expect do
          post admin_test_suites_path, params: valid_params
        end.to change(TestSuite, :count).by(1)
      end

      it "redirects to the new test suite" do
        post admin_test_suites_path, params: valid_params
        expect(response).to redirect_to(admin_test_suite_path(TestSuite.last))
      end

      it "renders new with invalid params" do
        post admin_test_suites_path,
             params: { test_suite: { name: "", agent_id: agent.id } }
        expect(response).to have_http_status(:unprocessable_content)
      end

      context "with mission suite type" do
        let(:mission) { create(:mission) }

        it "creates a mission test suite" do
          expect do
            post admin_test_suites_path,
                 params: { test_suite: { name: "Mission Suite", suite_type: "mission", mission_id: mission.id } }
          end.to change(TestSuite, :count).by(1)

          suite = TestSuite.last
          expect(suite).to be_mission
          expect(suite.mission).to eq(mission)
        end
      end
    end

    describe "GET /test_suites/:id/edit" do
      let(:suite) { create(:test_suite, agent:) }

      it "returns a successful response" do
        get edit_admin_test_suite_path(suite)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /test_suites/:id" do
      let(:suite) { create(:test_suite, agent:) }

      it "updates the test suite with valid params" do
        patch admin_test_suite_path(suite),
              params: { test_suite: { name: "Updated Name" } }
        expect(suite.reload.name).to eq("Updated Name")
        expect(response).to redirect_to(admin_test_suite_path(suite))
      end

      it "renders edit with invalid params" do
        patch admin_test_suite_path(suite),
              params: { test_suite: { name: "" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "DELETE /test_suites/:id" do
      let!(:suite) { create(:test_suite, agent:) }

      it "destroys the test suite" do
        expect do
          delete admin_test_suite_path(suite)
        end.to change(TestSuite, :count).by(-1)
      end

      it "redirects to the index" do
        delete admin_test_suite_path(suite)
        expect(response).to redirect_to(admin_test_suites_path)
      end
    end

    describe "POST /test_suites/:id/run_suite" do
      let(:suite) { create(:test_suite, :with_test_cases, agent:) }

      it "creates a running run and redirects" do
        expect do
          post run_suite_admin_test_suite_path(suite)
        end.to change(TestSuiteRun, :count).by(1)

        run = TestSuiteRun.last

        expect(response).to redirect_to(
          admin_test_suite_test_suite_run_path(suite, run),
        )
        expect(run).to be_running
        expect(run.started_at).to be_present
      end

      it "enqueues the execution job" do
        expect do
          post run_suite_admin_test_suite_path(suite)
        end.to have_enqueued_job(TestSuiteExecutionJob)

        run = TestSuiteRun.last
        expect(TestSuiteExecutionJob).to have_been_enqueued.with(run.id, tenant_id: suite.agent.operation.tenant_id)
      end

      it "enqueues mission suite runs with the mission tenant id" do
        mission = create(:mission, operation: agent.operation)
        mission_suite = create(:test_suite, :mission_suite, mission:)
        create(:test_case, :mission_case, test_suite: mission_suite)

        expect do
          post run_suite_admin_test_suite_path(mission_suite)
        end.to have_enqueued_job(TestSuiteExecutionJob)

        run = TestSuiteRun.last
        expect(TestSuiteExecutionJob).to have_been_enqueued.with(run.id, tenant_id: mission.operation.tenant_id)
      end

      context "when suite cannot run" do
        let(:suite) { create(:test_suite, agent:) } # no test cases

        it "redirects with alert" do
          post run_suite_admin_test_suite_path(suite)
          expect(response).to redirect_to(admin_test_suite_path(suite))
          expect(flash[:alert]).to eq(I18n.t("test_suites.cannot_run"))
        end
      end
    end

    describe "#test_suite_tenant_id" do
      it "prefers the agent tenant, falls back to the mission tenant, and returns nil otherwise", :aggregate_failures do
        controller = Admin::TestSuitesController.new
        mission = create(:mission)
        agent_suite = instance_double(TestSuite, agent:, mission: nil)
        mission_suite = instance_double(TestSuite, agent: nil, mission:)
        empty_suite = instance_double(TestSuite, agent: nil, mission: nil)

        expect(controller.send(:test_suite_tenant_id, agent_suite)).to eq(agent.operation.tenant_id)
        expect(controller.send(:test_suite_tenant_id, mission_suite)).to eq(mission.operation.tenant_id)
        expect(controller.send(:test_suite_tenant_id, empty_suite)).to be_nil
      end
    end

    describe "GET /test_suites/model_options" do
      it "returns a response with no connector" do
        get model_options_admin_agents_path,
            params: {
              frame_id: "evaluation_model_select", field_prefix: "test_suite",
              field_name: "evaluation_model_id", required: "false",
            }
        expect(response).to have_http_status(:ok)
      end

      it "returns models for an LLM connector" do
        connector = create(:connector, :llm_provider, :enabled)
        get model_options_admin_agents_path,
            params: {
              connector_id: connector.id, frame_id: "evaluation_model_select",
              field_prefix: "test_suite", field_name: "evaluation_model_id", required: "false",
            }
        expect(response).to have_http_status(:ok)
      end

      it "returns models for a non-LLM connector" do
        connector = create(:connector, :sql_database, :enabled)
        get model_options_admin_agents_path,
            params: {
              connector_id: connector.id, frame_id: "evaluation_model_select",
              field_prefix: "test_suite", field_name: "evaluation_model_id", required: "false",
            }
        expect(response).to have_http_status(:ok)
      end

      it "passes selected_model_id when provided" do
        get model_options_admin_agents_path,
            params: {
              selected_model_id: "gpt-4", frame_id: "evaluation_model_select",
              field_prefix: "test_suite", field_name: "evaluation_model_id", required: "false",
            }
        expect(response).to have_http_status(:ok)
      end
    end

    describe "form data loading with LLM connectors" do
      let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
      let(:suite) do
        create(:test_suite, agent:, evaluation_llm_connector: llm_connector)
      end

      it "loads evaluation models for edit" do
        get edit_admin_test_suite_path(suite)
        expect(response).to have_http_status(:ok)
      end

      it "loads evaluation models for new" do
        get new_admin_test_suite_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
