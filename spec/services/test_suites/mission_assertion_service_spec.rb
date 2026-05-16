# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::MissionAssertionService do
  let(:test_case) do
    build(:test_case, :mission_case,
          expected_status: "completed",
          expected_variables: {},
          match_type: "exact",)
  end

  let(:mission_run) do
    instance_double(MissionRun, status: "completed", variables: {})
  end

  describe ".call" do
    subject(:result) { described_class.call(test_case:, mission_run:) }

    context "when status matches and no expected variables" do
      it "returns passed" do
        expect(result[:passed]).to be true
        expect(result[:analysis]).to include("Status matched")
      end
    end

    context "when status does not match" do
      let(:mission_run) { instance_double(MissionRun, status: "failed", variables: {}) }

      it "returns failed with mismatch message" do
        expect(result[:passed]).to be false
        expect(result[:analysis]).to include('expected "completed" but got "failed"')
      end
    end

    context "with exact variable matching" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "count" => 5, "name" => "test" },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed", variables: { "count" => 5, "name" => "test" })
      end

      it "passes when all variables match exactly" do
        expect(result[:passed]).to be true
        expect(result[:analysis]).to include("2 expected variables matched (exact mode)")
      end
    end

    context "with exact matching and extra variables" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "count" => 5 },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed", variables: { "count" => 5, "extra" => "val" })
      end

      it "fails due to unexpected variables" do
        expect(result[:passed]).to be false
        expect(result[:analysis]).to include("Unexpected variables: extra")
      end
    end

    context "with exact matching and value mismatch" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "count" => 5 },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed", variables: { "count" => 10 })
      end

      it "fails with value mismatch message" do
        expect(result[:passed]).to be false
        expect(result[:analysis]).to include('Variable "count"')
      end
    end

    context "with partial variable matching" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "name" => "test" },
              match_type: "partial",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed",
                                    variables: { "name" => "test", "extra" => "ignored" },)
      end

      it "passes when subset of variables match" do
        expect(result[:passed]).to be true
      end
    end

    context "with partial matching and missing variable" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "missing_key" => "value" },
              match_type: "partial",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed", variables: { "other" => "value" })
      end

      it "fails with not found message" do
        expect(result[:passed]).to be false
        expect(result[:analysis]).to include('Variable "missing_key" not found')
      end
    end

    context "when mission_run variables are nil" do
      let(:mission_run) { instance_double(MissionRun, status: "completed", variables: nil) }

      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "key" => "val" },
              match_type: "partial",)
      end

      it "handles nil variables gracefully" do
        expect(result[:passed]).to be false
      end
    end

    context "with numeric normalization" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "count" => 5 },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed", variables: { "count" => 5.0 })
      end

      it "matches integers and floats" do
        expect(result[:passed]).to be true
      end
    end

    context "with internal variable keys excluded from exact matching" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "result" => "ok" },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed",
                                    variables: { "result" => "ok", "_current_node_id" => "n1" },)
      end

      it "ignores internal variables" do
        expect(result[:passed]).to be true
      end
    end

    context "with hash value normalization" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "data" => { key: "val" } },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed",
                                    variables: { "data" => { "key" => "val" } },)
      end

      it "normalizes hash keys to strings for comparison" do
        expect(result[:passed]).to be true
      end
    end

    context "with array value normalization" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "items" => [1, 2, 3] },
              match_type: "exact",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed",
                                    variables: { "items" => [1.0, 2.0, 3.0] },)
      end

      it "normalizes array values" do
        expect(result[:passed]).to be true
      end
    end

    context "with partial matching and value mismatch" do
      let(:test_case) do
        build(:test_case, :mission_case,
              expected_status: "completed",
              expected_variables: { "name" => "expected" },
              match_type: "partial",)
      end

      let(:mission_run) do
        instance_double(MissionRun, status: "completed",
                                    variables: { "name" => "actual" },)
      end

      it "fails with value mismatch message" do
        expect(result[:passed]).to be false
        expect(result[:analysis]).to include('Variable "name"')
      end
    end
  end
end
