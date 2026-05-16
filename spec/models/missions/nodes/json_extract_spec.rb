# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::JsonExtract do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns json_extract" do
      expect(described_class.node_type).to eq("json_extract")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires source" do
      expect(described_class.required_field_keys).to eq(["source"])
    end
  end

  describe ".variable_schema" do
    it "declares dynamic outputs" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("*")
    end
  end

  describe ".dynamic_output_variables" do
    it "accepts extraction hashes directly" do
      outputs = described_class.dynamic_output_variables(
        "extractions" => { "email" => "data.user.email" },
      )

      expect(outputs).to contain_exactly(include(name: "email", description: "Extracted JSON value"))
    end

    it "parses extraction hashes from JSON strings and skips blank names" do
      outputs = described_class.dynamic_output_variables(
        "extractions" => '{"":"ignored","email":"data.user.email"}',
      )

      expect(outputs).to contain_exactly(include(name: "email", description: "Extracted JSON value"))
    end

    it "returns an empty array for malformed or missing extraction payloads" do
      expect(described_class.dynamic_output_variables("extractions" => "{bad-json}")).to eq([])
      expect(described_class.dynamic_output_variables("extractions" => nil)).to eq([])
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "parses simple JSON" do
      json = '{"name": "Alice", "age": 30}'
      context.set_variable("_current_node_data", { "source" => json })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["parsed"]).to eq({ "name" => "Alice", "age" => 30 })
    end

    it "extracts values by dot path" do
      json = '{"data": {"user": {"email": "alice@example.com", "name": "Alice"}}}'
      context.set_variable("_current_node_data", {
                             "source" => json,
                             "extractions" => {
                               "email" => "data.user.email",
                               "name" => "data.user.name",
                             },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["email"]).to eq("alice@example.com")
      expect(result.variables["name"]).to eq("Alice")
    end

    it "handles array index in path" do
      json = '{"items": [{"id": 1}, {"id": 2}, {"id": 3}]}'
      context.set_variable("_current_node_data", {
                             "source" => json,
                             "extractions" => { "second_id" => "items.1.id" },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["second_id"]).to eq(2)
    end

    it "extracts values from root arrays" do
      json = '[{"id":"cap-1","title":"Lead"},{"id":"cap-2","title":"Deputy"}]'
      context.set_variable("_current_node_data", {
                             "source" => json,
                             "extractions" => {
                               "first_id" => "0.id",
                               "first_item" => "0",
                             },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["parsed"]).to eq(
        [
          { "id" => "cap-1", "title" => "Lead" },
          { "id" => "cap-2", "title" => "Deputy" },
        ],
      )
      expect(result.variables["first_id"]).to eq("cap-1")
      expect(result.variables["first_item"]).to eq({ "id" => "cap-1", "title" => "Lead" })
    end

    it "returns nil for missing paths" do
      json = '{"name": "Alice"}'
      context.set_variable("_current_node_data", {
                             "source" => json,
                             "extractions" => { "missing" => "nonexistent.path" },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["missing"]).to be_nil
    end

    it "fails with invalid JSON" do
      context.set_variable("_current_node_data", { "source" => "not json" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid JSON")
    end

    it "fails with blank source" do
      context.set_variable("_current_node_data", { "source" => "" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No JSON source")
    end

    it "interpolates variables in source" do
      context.set_variable("json_data", '{"result": "ok"}')
      context.set_variable("_current_node_data", { "source" => "{{json_data}}" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["parsed"]).to eq({ "result" => "ok" })
    end

    it "returns the full object when extraction path is blank" do
      json = '{"name": "Alice"}'
      context.set_variable("_current_node_data", {
                             "source" => json,
                             "extractions" => { "full" => "" },
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["full"]).to eq({ "name" => "Alice" })
    end
  end

  describe "#validate_config!" do
    it "accepts a literal JSON source" do
      expect { node.validate_config!("source" => '{"name":"Alice"}') }.not_to raise_error
    end

    it "accepts a template variable source" do
      expect { node.validate_config!("source" => "{{node.variable}}") }.not_to raise_error
    end

    it "rejects a bare plain string source" do
      expect { node.validate_config!("source" => "node.variable") }
        .to raise_error(ArgumentError, /plain strings are not allowed/)
    end
  end
end
