# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Input do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns input" do
      expect(described_class.node_type).to eq("input")
    end
  end

  describe ".node_category" do
    it "is input_output" do
      expect(described_class.node_category).to eq(:input_output)
    end
  end

  describe ".variable_schema" do
    it "declares dynamic outputs" do
      schema = described_class.variable_schema
      expect(schema.outputs.first.name).to eq("*")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe ".extract_variables" do
    it "adds trigger variables with field_type metadata", :aggregate_failures do
      data = {
        "label" => "Start",
        "fields" => [
          { "variable_name" => "query", "field_type" => "string", "label" => "Query", "required" => true },
          { "variable_name" => "count", "field_type" => "number", "label" => "Count" },
        ],
      }
      variables = []
      seen = Set.new
      described_class.extract_variables(data, "Start", variables, seen)

      expect(variables.size).to eq(2)
      query_var = variables.find { |v| v[:key] == "query" }
      expect(query_var[:category]).to eq("trigger")
      expect(query_var[:field_type]).to eq("string")
      expect(query_var[:description]).to eq("Query")
      expect(query_var[:required]).to be(true)

      count_var = variables.find { |v| v[:key] == "count" }
      expect(count_var[:field_type]).to eq("number")
      expect(count_var[:description]).to eq("Count")
      expect(count_var[:required]).to be(false)
    end

    it "parses fields from a JSON string" do
      data = {
        "label" => "Start",
        "fields" => '[{"variable_name":"q","field_type":"string","label":"Q"}]',
      }
      variables = []
      seen = Set.new
      described_class.extract_variables(data, "Start", variables, seen)
      expect(variables.size).to eq(1)
      expect(variables.first[:key]).to eq("q")
    end

    it "returns early when fields is not an array or string" do
      variables = []
      seen = Set.new
      described_class.extract_variables({ "fields" => nil }, "Start", variables, seen)
      expect(variables).to be_empty
    end
  end

  describe ".dynamic_output_variables" do
    it "parses fields from JSON strings and maps output types" do
      outputs = described_class.dynamic_output_variables(
        "fields" => <<~JSON.squish,
          [
            {"variable_name":"count","field_type":"number","label":"Count"},
            {"variable_name":"enabled","field_type":"boolean"},
            {"variable_name":"tags","field_type":"string_array"}
          ]
        JSON
      )

      expect(outputs).to include(include(name: "count", type: :number, description: "Count"))
      expect(outputs).to include(include(name: "enabled", type: :boolean))
      expect(outputs).to include(include(name: "tags", type: :array))
    end

    it "returns an empty array for malformed or missing field payloads" do
      expect(described_class.dynamic_output_variables("fields" => "{bad-json}")).to eq([])
      expect(described_class.dynamic_output_variables("fields" => nil)).to eq([])
    end
  end

  describe "#validate_config!" do
    it "accepts stringified field arrays" do
      expect do
        node.validate_config!("fields" => '[{"variable_name":"username","field_type":"string"}]')
      end.not_to raise_error
    end

    it "rejects stringified field payloads that parse to a non-array" do
      expect do
        node.validate_config!("fields" => '{"variable_name":"username"}')
      end.to raise_error(ArgumentError, "fields must be an array of input field definitions")
    end

    it "rejects malformed JSON field payloads" do
      expect do
        node.validate_config!("fields" => "{bad-json}")
      end.to raise_error(ArgumentError, "fields must be an array of input field definitions")
    end

    it "rejects unsupported raw field payload types" do
      expect do
        node.validate_config!("fields" => 123)
      end.to raise_error(ArgumentError, "fields must be an array of input field definitions")
    end

    it "rejects non-hash field definitions" do
      expect do
        node.validate_config!("fields" => ["username"])
      end.to raise_error(ArgumentError, "fields[0] must be an object")
    end

    it "rejects unsupported field_type values" do
      expect do
        node.validate_config!("fields" => [{ "variable_name" => "username", "field_type" => "uuid" }])
      end.to raise_error(ArgumentError, /fields\[0\]\.field_type must be one of:/)
    end
  end

  describe "#execute" do
    let(:fields) do
      [
        { "variable_name" => "name", "label" => "Name", "field_type" => "string", "required" => true, "config" => {} },
        { "variable_name" => "age", "label" => "Age", "field_type" => "number", "required" => false,
          "config" => { "default_value" => 25 }, },
      ]
    end

    before do
      context.set_variable("_current_node_data", { "fields" => fields })
    end

    it "extracts variables from trigger_data" do
      context.set_variable("_trigger_data", { "name" => "Alice", "age" => 30 })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables).to eq({ "name" => "Alice", "age" => 30.0 })
    end

    it "uses default values when trigger_data is missing" do
      context.set_variable("_trigger_data", { "name" => "Bob" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["name"]).to eq("Bob")
      expect(result.variables["age"]).to eq(25.0)
    end

    it "fails when a required field is missing" do
      context.set_variable("_trigger_data", { "age" => 30 })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Required field 'name' is missing")
    end

    it "coerces boolean values" do
      fields = [
        { "variable_name" => "active", "field_type" => "boolean", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "active" => "true" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["active"]).to be(true)
    end

    it "coerces string array values" do
      fields = [
        { "variable_name" => "tags", "field_type" => "string_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "tags" => ["a", "b", "c"] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["tags"]).to eq(["a", "b", "c"])
    end

    it "coerces JSON string values" do
      fields = [
        { "variable_name" => "data", "field_type" => "json", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "data" => '{"key": "value"}' })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["data"]).to eq({ "key" => "value" })
    end

    it "handles empty fields list" do
      context.set_variable("_current_node_data", { "fields" => [] })
      context.set_variable("_trigger_data", {})

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables).to eq({ "input" => nil })
    end

    it "handles missing node_data gracefully" do
      no_data_context = Missions::ExecutionContext.new(mission_run: run)

      result = node.execute(no_data_context)

      expect(result).to be_success
      expect(result.variables).to eq({ "input" => nil })
    end

    it "sets variables on the execution context" do
      context.set_variable("_trigger_data", { "name" => "Charlie" })

      node.execute(context)

      expect(context.get_variable("name")).to eq("Charlie")
    end

    it "skips fields with blank variable_name" do
      fields = [
        { "variable_name" => "", "field_type" => "string", "required" => false, "config" => {} },
        { "variable_name" => "keep", "field_type" => "string", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "keep" => "yes" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables).to eq({ "keep" => "yes" })
    end

    it "returns nil for non-required field missing from trigger_data" do
      fields = [
        { "variable_name" => "optional", "field_type" => "string", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", {})

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["optional"]).to be_nil
    end

    it "coerces number from string" do
      fields = [
        { "variable_name" => "count", "field_type" => "number", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "count" => "42" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["count"]).to eq(42.0)
    end

    it "coerces number_array values" do
      fields = [
        { "variable_name" => "nums", "field_type" => "number_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "nums" => [1, "2.5", 3] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["nums"]).to eq([1, 2.5, 3])
    end

    it "coerces boolean_array values" do
      fields = [
        { "variable_name" => "flags", "field_type" => "boolean_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "flags" => ["true", "false", true] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["flags"]).to eq([true, false, true])
    end

    it "coerces date_array values" do
      fields = [
        { "variable_name" => "dates", "field_type" => "date_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "dates" => ["2026-01-01", "2026-06-15"] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["dates"]).to eq(["2026-01-01", "2026-06-15"])
    end

    it "coerces datetime_array values" do
      fields = [
        { "variable_name" => "timestamps", "field_type" => "datetime_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "timestamps" => ["2026-01-01T10:00:00Z"] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["timestamps"]).to eq(["2026-01-01T10:00:00Z"])
    end

    it "coerces file_array values" do
      fields = [
        { "variable_name" => "files", "field_type" => "file_array", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "files" => ["file1.txt", "file2.txt"] })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["files"]).to eq(["file1.txt", "file2.txt"])
    end

    it "passes through JSON values that are already parsed" do
      fields = [
        { "variable_name" => "data", "field_type" => "json", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "data" => { "already" => "parsed" } })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["data"]).to eq({ "already" => "parsed" })
    end

    it "returns raw value when JSON parsing fails" do
      fields = [
        { "variable_name" => "bad", "field_type" => "json", "required" => false, "config" => {} },
      ]
      context.set_variable("_current_node_data", { "fields" => fields })
      context.set_variable("_trigger_data", { "bad" => "not valid json{" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["bad"]).to eq("not valid json{")
    end
  end
end
