# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::FlowPersistenceNormalizer do
  describe ".parse_and_normalize" do
    def non_blank_json_input
      {
        nodes: [{ id: "n1", type: "llm", data: { label: "Draft Reply", temperature: "0.7" } }],
        edges: [],
        global_variables: [{ key: "api key", value: "secret", type: "string" }],
      }.to_json
    end

    def expected_llm_node
      {
        "id" => "n1",
        "type" => "llm",
        "position" => { "x" => 0, "y" => 0 },
        "data" => {
          "label" => "Draft Reply",
          "llm_config_source" => "system_preference",
          "name" => "draft_reply",
          "temperature" => 0.7,
        },
      }
    end

    it "returns an empty flow for blank input" do
      expect(described_class.parse_and_normalize(nil)).to eq({ "nodes" => [], "edges" => [] })
      expect(described_class.parse_and_normalize("")).to eq({ "nodes" => [], "edges" => [] })
    end

    it "normalizes non-blank JSON input" do
      normalized = described_class.parse_and_normalize(non_blank_json_input)

      expect(normalized["nodes"]).to eq([expected_llm_node])
      expect(normalized["edges"]).to eq([])
      expect(normalized["global_variables"]).to eq([{ "key" => "api_key", "value" => "secret", "type" => "string" }])
    end

    it "normalizes non-string hash input" do
      normalized = described_class.parse_and_normalize(
        {
          "nodes" => [{ "id" => "n2", "type" => "input" }],
          "edges" => [],
        },
      )

      expect(normalized).to eq(
        {
          "nodes" => [{ "id" => "n2", "type" => "input", "position" => { "x" => 0, "y" => 0 } }],
          "edges" => [],
        },
      )
    end

    it "assigns unique node prefixes when labels repeat" do
      normalized = described_class.parse_and_normalize(
        {
          "nodes" => [
            { "id" => "n1", "type" => "json_extract", "data" => { "label" => "JSON Extract" } },
            { "id" => "n2", "type" => "json_extract", "data" => { "label" => "JSON Extract" } },
            { "id" => "n3", "type" => "json_extract", "data" => { "label" => "JSON Extract" } },
          ],
          "edges" => [],
        },
      )

      expect(normalized.dig("nodes", 0, "data", "name")).to eq("json_extract")
      expect(normalized.dig("nodes", 1, "data", "name")).to eq("json_extract_2")
      expect(normalized.dig("nodes", 2, "data", "name")).to eq("json_extract_3")
    end
  end
end
