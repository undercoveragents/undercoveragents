# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::NodeInputSnapshot do
  let(:mission) { create(:mission) }
  let(:run) { create(:mission_run, mission:) }
  let(:http_request_data) do
    {
      "url" => "https://api.example.com/users/{{name}}",
      "headers" => { "X-User" => "{{name}}" },
      "verify_ssl" => "false",
      "connect_timeout" => "1.5",
      "read_timeout" => "2",
      "write_timeout" => "slow",
      "max_retries" => "3",
      "retry_interval_ms" => 250,
    }
  end
  let(:llm_data) do
    {
      "thinking_budget" => "512",
      "temperature" => 0.4,
      "file_variables" => "[\"doc\"]",
      "tool_ids" => [1, 2],
    }
  end
  let(:input_trigger_data) do
    {
      "age" => "5",
      "settings" => "{bad-json}",
      "flag" => "true",
    }
  end
  let(:input_fields_data) do
    {
      "fields" => [
        { "variable_name" => "age", "field_type" => "number" },
        { "variable_name" => "settings", "field_type" => "json" },
        {
          "variable_name" => "limit",
          "field_type" => "number",
          "config" => { "default_value" => 10 },
        },
        { "variable_name" => "flag", "field_type" => "boolean" },
        { "variable_name" => "missing", "field_type" => "string" },
        { "variable_name" => "", "field_type" => "string" },
        "skip me",
      ],
    }
  end
  let(:context) do
    Missions::ExecutionContext.new(
      mission_run: run,
      variables: {
        "name" => "Alice",
        "count" => 3,
        "items" => [1, 2, 3],
        "input" => "Fallback input",
      },
    )
  end

  def snapshot(node_type, node_data)
    described_class.new(node_type:, node_data:, context:).call
  end

  describe "#call" do
    it "resolves template, boolean, and numeric http request contracts" do
      http_snapshot = snapshot("http_request", http_request_data)

      expect(http_snapshot).to include(
        "url" => "https://api.example.com/users/Alice",
        "headers" => { "X-User" => "Alice" },
        "verify_ssl" => false,
        "connect_timeout" => 1.5,
        "read_timeout" => 2,
        "write_timeout" => "slow",
        "max_retries" => 3,
        "retry_interval_ms" => 250,
      )
    end

    it "resolves integer and array llm contracts" do
      llm_snapshot = snapshot("llm", llm_data)

      expect(llm_snapshot).to include(
        "thinking_budget" => 512,
        "temperature" => 0.4,
        "file_variables" => ["doc"],
        "tool_ids" => [1, 2],
      )
    end

    it "resolves nested template hashes and arrays" do
      mission_snapshot = snapshot("mission", {
                                    "mission_id" => "42",
                                    "input_variables" => {
                                      "greeting" => "Hello {{name}}",
                                      "tags" => ["{{name}}", 3],
                                      "details" => { "owner" => "{{name}}" },
                                    },
                                  })

      expect(mission_snapshot).to include(
        "mission_id" => "42",
        "input_variables" => {
          "greeting" => "Hello Alice",
          "tags" => ["Alice", 3],
          "details" => { "owner" => "Alice" },
        },
      )
    end

    it "resolves formula, collection, assignment, and output-selection contracts" do
      condition_snapshot = snapshot("condition", { "expression" => "count > 2" })
      iterator_snapshot = snapshot("iterator", { "collection" => "items" })
      set_variable_snapshot = snapshot("set_variable", {
                                         "assignments" => {
                                           "greeting" => "Hello {{name}}",
                                           "count" => 5,
                                         },
                                       })
      output_snapshot = snapshot("output", { "selected_variables" => "\"llm.response\"" })

      expect(condition_snapshot).to eq({ "expression" => true })
      expect(iterator_snapshot).to eq({ "collection" => [1, 2, 3] })
      expect(set_variable_snapshot).to eq({ "assignments" => { "greeting" => "Hello Alice", "count" => 5 } })
      expect(output_snapshot).to eq({ "selected_variables" => ["llm.response"] })
    end

    it "compacts nil collection references from the snapshot" do
      expect(snapshot("iterator", { "collection" => nil })).to eq({})
    end

    it "resolves input field values, defaults, nils, and coercion fallbacks" do
      context.set_variable("_trigger_data", input_trigger_data)

      input_snapshot = snapshot("input", input_fields_data)

      expect(input_snapshot).to eq(
        "fields" => {
          "age" => 5.0,
          "settings" => "{bad-json}",
          "limit" => 10,
          "flag" => true,
          "missing" => nil,
        },
      )
    end

    it "uses the raw input variable when an input node has no fields" do
      input_snapshot = snapshot("input", { "fields" => nil })

      expect(input_snapshot).to eq({ "fields" => { "input" => "Fallback input" } })
    end

    it "normalizes assignment map payloads" do
      json_assignment_snapshot = snapshot("set_variable", { "assignments" => '{"greeting":"Hello {{name}}"}' })
      assignment_snapshot = snapshot("set_variable", { "assignments" => "\"hello\"" })
      malformed_assignment_snapshot = snapshot("set_variable", { "assignments" => "{bad-json}" })
      non_hash_assignment_snapshot = snapshot("set_variable", { "assignments" => 7 })

      expect(json_assignment_snapshot).to eq({ "assignments" => { "greeting" => "Hello Alice" } })
      expect(assignment_snapshot).to eq({ "assignments" => { "value" => "hello" } })
      expect(malformed_assignment_snapshot).to eq({ "assignments" => {} })
      expect(non_hash_assignment_snapshot).to eq({ "assignments" => {} })
    end

    it "normalizes malformed output selection payloads" do
      selection_snapshot = snapshot("output", { "selected_variables" => 7 })
      malformed_selection_snapshot = snapshot("output", { "selected_variables" => "not-json" })

      expect(selection_snapshot).to eq({ "selected_variables" => [7] })
      expect(malformed_selection_snapshot).to eq({ "selected_variables" => [] })
    end

    it "drops unsupported node_data payloads before building the snapshot" do
      expect(snapshot("unknown", ["not", "a", "hash"])).to eq({})
    end

    it "falls back to filtered node data for unknown node types" do
      fallback_snapshot = snapshot(
        "unknown",
        {
          "label" => "Ignored label",
          "name" => "Ignored name",
          "description" => "Ignored description",
          "output_ports" => [{ "key" => "default" }],
          "custom" => { "nested" => ["x", 1] },
        },
      )

      expect(fallback_snapshot).to eq({ "custom" => { "nested" => ["x", 1] } })
    end

    it "falls back to raw node data when contract snapshot resolution raises" do
      allow_any_instance_of(described_class).to receive(:snapshot_from_contracts).and_raise(StandardError, "boom") # rubocop:disable RSpec/AnyInstance

      fallback_snapshot = snapshot(
        "text_template",
        {
          "template" => "Hello {{name}}",
          "label" => "Ignored label",
        },
      )

      expect(fallback_snapshot).to eq({ "template" => "Hello {{name}}" })
    end

    it "returns non-hash snapshots unchanged before compacting" do
      allow_any_instance_of(described_class).to receive(:snapshot_from_contracts).and_return(["value"]) # rubocop:disable RSpec/AnyInstance

      result = snapshot("text_template", { "template" => "Hello {{name}}" })
      expect(result).to eq(["value"])
    end

    it "returns safe fallbacks when formula or collection resolution fails" do
      resolver = instance_double(Missions::ValueResolver)
      allow(Missions::ValueResolver).to receive(:new).with(context).and_return(resolver)
      allow(resolver).to receive(:formula_or_literal).and_raise(StandardError, "boom")
      allow(resolver).to receive(:collection).and_raise(Missions::ExecutionError, "missing")

      formula_snapshot = snapshot("condition", { "expression" => "Hello {{name}}" })
      collection_snapshot = snapshot("iterator", { "collection" => "missing_items" })

      expect(formula_snapshot).to eq({ "expression" => "Hello Alice" })
      expect(collection_snapshot).to eq({ "collection" => "missing_items" })
    end
  end
end
