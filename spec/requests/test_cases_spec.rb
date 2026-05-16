# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TestCases" do
  let(:agent) { create(:agent) }
  let(:test_suite) { create(:test_suite, agent:) }

  describe "POST /test_cases" do
    let(:valid_params) do
      { test_case: { prompt: "What is 2+2?", expected_answer: "4", match_type: "exact", position: 0 } }
    end

    it "creates a new test case with valid params" do
      expect do
        post admin_test_suite_test_cases_path(test_suite),
             params: valid_params
      end.to change(TestCase, :count).by(1)
    end

    it "responds with turbo_stream on turbo request" do
      post admin_test_suite_test_cases_path(test_suite),
           params: valid_params,
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="test-cases-list"')
    end

    it "redirects on HTML request" do
      post admin_test_suite_test_cases_path(test_suite),
           params: valid_params
      expect(response).to redirect_to(admin_test_suite_path(test_suite))
    end

    it "normalizes behavior assertion params" do
      post admin_test_suite_test_cases_path(test_suite),
           params: { test_case: {
             prompt: "Check behavior",
             expected_answer: "Done",
             match_type: "exact",
             position: 0,
             disallow_child_chats: "1",
             expected_tool_names: [" list_resources ", ""],
             required_keywords: "Done, Created",
             forbidden_keywords: "cannot\nblocked",
           } }

      test_case = TestCase.last
      expect(test_case).to be_disallow_child_chats
      expect(test_case.expected_tool_names).to eq(["list_resources"])
      expect(test_case.required_keywords).to eq(["Done", "Created"])
      expect(test_case.forbidden_keywords).to eq(["cannot", "blocked"])
    end

    context "with invalid params" do
      let(:invalid_params) { { test_case: { prompt: "", expected_answer: "", match_type: "exact", position: 0 } } }

      it "does not create a test case" do
        expect do
          post admin_test_suite_test_cases_path(test_suite),
               params: invalid_params
        end.not_to change(TestCase, :count)
      end

      it "responds with turbo_stream error on turbo request" do
        post admin_test_suite_test_cases_path(test_suite),
             params: invalid_params,
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "redirects with alert on HTML request" do
        post admin_test_suite_test_cases_path(test_suite),
             params: invalid_params
        expect(response).to redirect_to(admin_test_suite_path(test_suite))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "PATCH /test_cases/:id" do
    let!(:test_case) { create(:test_case, test_suite:) }

    it "updates the test case with valid params" do
      patch admin_test_suite_test_case_path(test_suite, test_case),
            params: { test_case: { prompt: "Updated prompt", expected_answer: "Updated answer",
                                   match_type: "semantic", position: 1, } }
      expect(test_case.reload.prompt).to eq("Updated prompt")
    end

    it "responds with turbo_stream on turbo request" do
      patch admin_test_suite_test_case_path(test_suite, test_case),
            params: { test_case: { prompt: "Updated", expected_answer: "New", match_type: "exact", position: 0 } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end

    it "redirects on HTML request" do
      patch admin_test_suite_test_case_path(test_suite, test_case),
            params: { test_case: { prompt: "Updated", expected_answer: "New", match_type: "exact", position: 0 } }
      expect(response).to redirect_to(admin_test_suite_path(test_suite))
    end

    context "with invalid params" do
      it "responds with turbo_stream error on turbo request" do
        patch admin_test_suite_test_case_path(test_suite, test_case),
              params: { test_case: { prompt: "", expected_answer: "", match_type: "exact", position: 0 } },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "redirects with alert on HTML request" do
        patch admin_test_suite_test_case_path(test_suite, test_case),
              params: { test_case: { prompt: "", expected_answer: "", match_type: "exact", position: 0 } }
        expect(response).to redirect_to(admin_test_suite_path(test_suite))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "DELETE /test_cases/:id" do
    let!(:test_case) { create(:test_case, test_suite:) }

    it "destroys the test case" do
      expect do
        delete admin_test_suite_test_case_path(test_suite, test_case)
      end.to change(TestCase, :count).by(-1)
    end

    it "responds with turbo_stream on turbo request" do
      delete admin_test_suite_test_case_path(test_suite, test_case),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="test-cases-list"')
    end

    it "redirects on HTML request" do
      delete admin_test_suite_test_case_path(test_suite, test_case)
      expect(response).to redirect_to(admin_test_suite_path(test_suite))
    end
  end

  describe "POST /test_cases (mission suite)" do
    let(:mission) { create(:mission) }
    let(:mission_suite) { create(:test_suite, :mission_suite, mission:) }

    it "creates a mission test case with JSON variables" do
      expect do
        post admin_test_suite_test_cases_path(mission_suite),
             params: { test_case: {
               name: "Test Case 1",
               expected_status: "completed",
               match_type: "exact",
               position: 0,
               input_variables: '{"key": "value"}',
               expected_variables: '{"result": "ok"}',
             } }
      end.to change(TestCase, :count).by(1)

      tc = TestCase.last
      expect(tc.name).to eq("Test Case 1")
      expect(tc.input_variables).to eq({ "key" => "value" })
      expect(tc.expected_variables).to eq({ "result" => "ok" })
    end

    it "handles blank JSON variables gracefully" do
      post admin_test_suite_test_cases_path(mission_suite),
           params: { test_case: {
             name: "Blank Vars",
             expected_status: "completed",
             match_type: "partial",
             position: 0,
             input_variables: "",
             expected_variables: "",
           } }

      tc = TestCase.last
      expect(tc.input_variables).to eq({})
      expect(tc.expected_variables).to eq({})
    end

    it "handles invalid JSON gracefully" do
      post admin_test_suite_test_cases_path(mission_suite),
           params: { test_case: {
             name: "Bad JSON",
             expected_status: "completed",
             match_type: "partial",
             position: 0,
             input_variables: "not json",
             expected_variables: "{invalid",
           } }

      tc = TestCase.last
      expect(tc.input_variables).to eq({})
      expect(tc.expected_variables).to eq({})
    end
  end
end
