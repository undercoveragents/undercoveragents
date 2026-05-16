# frozen_string_literal: true

# == Schema Information
#
# Table name: missions
# Database name: primary
#
#  id                :bigint           not null, primary key
#  description       :text
#  flow_data         :jsonb            not null
#  flow_redo_history :jsonb            not null
#  flow_undo_history :jsonb            not null
#  name              :string           not null
#  slug              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operation_id      :bigint           not null
#
# Indexes
#
#  index_missions_on_name          (name)
#  index_missions_on_operation_id  (operation_id)
#  index_missions_on_slug          (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
require "rails_helper"

RSpec.describe Mission do
  describe "associations" do
    it { is_expected.to have_many(:mission_runs).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "friendly_id" do
    it "generates a slug from the name" do
      mission = create(:mission, name: "My Mission")
      expect(mission.slug).to eq("my-mission")
    end

    it "regenerates the slug when the name changes" do
      mission = create(:mission, name: "Original Name")
      mission.update!(name: "New Name")
      expect(mission.slug).to eq("new-name")
    end
  end

  describe "#input_fields" do
    let(:fields) do
      [
        { "variable_name" => "query", "field_type" => "string", "required" => true, "label" => "Query" },
        { "variable_name" => "limit", "field_type" => "number", "required" => false },
      ]
    end

    it "returns fields from the Input node" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{ "id" => "1", "type" => "input",
                                      "data" => { "fields" => fields }, }],
                        "edges" => [],
                      },)
      expect(mission.input_fields).to eq(fields)
    end

    it "returns empty array when no Input node exists" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })
      expect(mission.input_fields).to eq([])
    end

    it "parses JSON-encoded fields" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{ "id" => "1", "type" => "input",
                                      "data" => { "fields" => fields.to_json }, }],
                        "edges" => [],
                      },)
      expect(mission.input_fields).to eq(fields)
    end

    it "returns empty array for invalid JSON" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{ "id" => "1", "type" => "input",
                                      "data" => { "fields" => "bad{json" }, }],
                        "edges" => [],
                      },)
      expect(mission.input_fields).to eq([])
    end

    it "returns empty array when fields is not an Array" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{ "id" => "1", "type" => "input",
                                      "data" => { "fields" => "true" }, }],
                        "edges" => [],
                      },)
      expect(mission.input_fields).to eq([])
    end

    it "returns empty array when flow_data is nil" do
      mission = build(:mission)
      allow(mission).to receive(:flow_data).and_return(nil)

      expect(mission.input_fields).to eq([])
    end
  end

  describe "#input_field_names" do
    it "returns the variable names" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "input",
                          "data" => {
                            "fields" => [
                              { "variable_name" => "query", "field_type" => "string" },
                              { "variable_name" => "limit", "field_type" => "number" },
                            ],
                          },
                        }],
                        "edges" => [],
                      },)
      expect(mission.input_field_names).to eq(["query", "limit"])
    end

    it "skips fields with blank variable_name" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "input",
                          "data" => {
                            "fields" => [
                              { "variable_name" => "query" },
                              { "variable_name" => "" },
                              { "variable_name" => nil },
                            ],
                          },
                        }],
                        "edges" => [],
                      },)
      expect(mission.input_field_names).to eq(["query"])
    end
  end

  describe "#input_field_definitions" do
    let(:mission) do
      build(:mission, flow_data: {
              "nodes" => [{
                "id" => "1",
                "type" => "input",
                "data" => {
                  "fields" => [
                    { "variable_name" => "query", "required" => true },
                    { "variable_name" => "limit", "field_type" => "number", "label" => "Limit" },
                    { "variable_name" => "" },
                  ],
                },
              }],
              "edges" => [],
            },)
    end

    let(:expected_definitions) do
      [
        { variable_name: "query", field_type: "string", required: true, label: "query" },
        { variable_name: "limit", field_type: "number", required: false, label: "Limit" },
      ]
    end

    it "normalizes labels, required flags, and types for input fields" do
      expect(mission.input_field_definitions).to eq(expected_definitions)
    end
  end

  describe "#output_field_names" do
    it "returns selected output variables" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "output",
                          "data" => { "selected_variables" => ["summary", "status", ""] },
                        }],
                        "edges" => [],
                      },)

      expect(mission.output_field_names).to eq(["summary", "status"])
    end

    it "returns an empty array when no output node exists" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })

      expect(mission.output_field_names).to eq([])
    end

    it "returns an empty array when flow_data is nil" do
      mission = build(:mission)
      allow(mission).to receive(:flow_data).and_return(nil)

      expect(mission.output_field_names).to eq([])
    end
  end

  describe "#output_field_definitions" do
    it "wraps output field names for mission IO responses" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "output",
                          "data" => { "selected_variables" => ["summary"] },
                        }],
                        "edges" => [],
                      },)

      expect(mission.output_field_definitions).to eq([{ variable_name: "summary" }])
    end
  end

  describe "#global_variable_keys" do
    it "returns non-blank global variable keys" do
      mission = build(:mission, flow_data: {
                        "nodes" => [],
                        "edges" => [],
                        "global_variables" => [
                          { "key" => "api_key" },
                          { "key" => "" },
                          { "key" => nil },
                        ],
                      },)

      expect(mission.global_variable_keys).to eq(["api_key"])
    end

    it "returns an empty array when no global variables are configured" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })

      expect(mission.global_variable_keys).to eq([])
    end

    it "returns an empty array when flow_data is nil" do
      mission = build(:mission)
      allow(mission).to receive(:flow_data).and_return(nil)

      expect(mission.global_variable_keys).to eq([])
    end
  end

  describe "#file_field_names" do
    it "returns names of file and file_array fields" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "input",
                          "data" => {
                            "fields" => [
                              { "variable_name" => "query", "field_type" => "string" },
                              { "variable_name" => "document", "field_type" => "file" },
                              { "variable_name" => "photos", "field_type" => "file_array" },
                            ],
                          },
                        }],
                        "edges" => [],
                      },)
      expect(mission.file_field_names).to eq(["document", "photos"])
    end

    it "returns empty array when no file fields exist" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "input",
                          "data" => {
                            "fields" => [{ "variable_name" => "query", "field_type" => "string" }],
                          },
                        }],
                        "edges" => [],
                      },)
      expect(mission.file_field_names).to eq([])
    end
  end

  describe "#file_fields?" do
    it "returns true when file fields exist" do
      mission = build(:mission, flow_data: {
                        "nodes" => [{
                          "id" => "1",
                          "type" => "input",
                          "data" => {
                            "fields" => [{ "variable_name" => "doc", "field_type" => "file" }],
                          },
                        }],
                        "edges" => [],
                      },)
      expect(mission.file_fields?).to be(true)
    end

    it "returns false when no file fields exist" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })
      expect(mission.file_fields?).to be(false)
    end
  end

  describe "#filter_trigger_data" do
    let(:mission) do
      build(:mission, flow_data: {
              "nodes" => [{
                "id" => "1",
                "type" => "input",
                "data" => {
                  "fields" => [
                    { "variable_name" => "query", "field_type" => "string" },
                    { "variable_name" => "limit", "field_type" => "number" },
                  ],
                },
              }],
              "edges" => [],
            },)
    end

    it "keeps only defined input field keys" do
      data = { "query" => "hello", "limit" => 10, "extra" => "removed" }
      expect(mission.filter_trigger_data(data)).to eq({ "query" => "hello", "limit" => 10 })
    end

    it "keeps runtime LLM config keys for runtime-supplied LLM nodes" do
      runtime_config = { "model" => "gpt-4.1" }
      data = { "query" => "hello", "_llm_config" => runtime_config, "extra" => "removed" }

      expect(mission.filter_trigger_data(data)).to eq({ "query" => "hello", "_llm_config" => runtime_config })
    end

    it "passes through when no input fields are defined" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })
      data = { "anything" => "goes" }
      expect(mission.filter_trigger_data(data)).to eq(data)
    end

    it "passes through non-Hash data" do
      expect(mission.filter_trigger_data("raw string")).to eq("raw string")
    end
  end

  describe "#validate_required_inputs" do
    let(:mission) do
      build(:mission, flow_data: {
              "nodes" => [{
                "id" => "1",
                "type" => "input",
                "data" => {
                  "fields" => [
                    { "variable_name" => "query", "field_type" => "string", "required" => true },
                    { "variable_name" => "limit", "field_type" => "number" },
                    { "variable_name" => "mode", "field_type" => "string", "required" => true,
                      "config" => { "default_value" => "fast" }, },
                  ],
                },
              }],
              "edges" => [],
            },)
    end

    it "returns names of missing required fields without defaults" do
      expect(mission.validate_required_inputs({ "limit" => 5 })).to eq(["query"])
    end

    it "returns empty when all required fields are present" do
      expect(mission.validate_required_inputs({ "query" => "hello" })).to eq([])
    end

    it "skips required fields that have default values" do
      expect(mission.validate_required_inputs({ "query" => "hello" })).not_to include("mode")
    end

    it "returns empty when no input fields are defined" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })
      expect(mission.validate_required_inputs({ "foo" => "bar" })).to eq([])
    end
  end

  describe "#flow_data=" do
    it "accepts a Hash directly" do
      mission = build(:mission, flow_data: { "nodes" => [], "edges" => [] })
      expect(mission.flow_data).to eq({ "nodes" => [], "edges" => [] })
    end

    it "parses a JSON string into a Hash" do
      mission = described_class.new
      mission.flow_data = '{"nodes":[{"id":"n1"}],"edges":[]}'
      expect(mission.flow_data).to eq({
                                        "nodes" => [{ "id" => "n1", "position" => { "x" => 0, "y" => 0 } }],
                                        "edges" => [],
                                      })
    end

    it "falls back to empty flow when given invalid JSON" do
      mission = described_class.new
      mission.flow_data = "not valid json {{{"
      expect(mission.flow_data).to eq({ "nodes" => [], "edges" => [] })
    end
  end
end
