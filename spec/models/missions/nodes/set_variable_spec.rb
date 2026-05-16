# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::SetVariable do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns set_variable" do
      expect(described_class.node_type).to eq("set_variable")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires assignments" do
      expect(described_class.required_field_keys).to eq(["assignments"])
    end
  end

  describe ".variable_schema" do
    it "declares dynamic output" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("*")
    end
  end

  describe "#output_ports" do
    it "has a default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe ".extract_variables" do
    it "extracts assignment keys and template variables" do
      variables = []
      seen = Set.new
      data = { "assignments" => { "greeting" => "Hello {{name}}" } }

      described_class.extract_variables(data, "SetVar", variables, seen)

      keys = variables.pluck(:key)
      expect(keys).to include("name")
      expect(seen).to include("greeting")
    end

    it "handles empty assignments" do
      variables = []
      seen = Set.new

      described_class.extract_variables({}, "SetVar", variables, seen)

      expect(variables).to be_empty
    end

    it "parses assignments from a JSON string" do
      variables = []
      seen = Set.new
      data = { "assignments" => '{"result":"{{input}}"}' }

      described_class.extract_variables(data, "SetVar", variables, seen)

      expect(seen).to include("result")
      keys = variables.pluck(:key)
      expect(keys).to include("input")
    end
  end

  describe ".dynamic_output_variables" do
    it "parses assignment hashes from JSON strings and skips blank names" do
      outputs = described_class.dynamic_output_variables(
        "assignments" => '{"":"ignored","status":"active"}',
      )

      expect(outputs).to contain_exactly(include(name: "status", description: "Assigned variable"))
    end

    it "returns an empty array for malformed or missing assignment payloads" do
      expect(described_class.dynamic_output_variables("assignments" => "{bad-json}")).to eq([])
      expect(described_class.dynamic_output_variables("assignments" => nil)).to eq([])
    end
  end

  describe "#execute" do
    it "sets literal string values" do
      context.set_variable("_current_node_data", {
                             "assignments" => { "status" => "active" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["status"]).to eq("active")
      expect(context.get_variable("status")).to eq("active")
    end

    it "evaluates arithmetic expressions" do
      context.set_variable("price", 10)
      context.set_variable("quantity", 3)
      context.set_variable("_current_node_data", {
                             "assignments" => { "total" => "price * quantity" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["total"]).to eq(30)
    end

    it "interpolates template variables" do
      context.set_variable("name", "World")
      context.set_variable("_current_node_data", {
                             "assignments" => { "greeting" => "Hello {{name}}" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["greeting"]).to include("World")
    end

    it "sets multiple variables" do
      context.set_variable("_current_node_data", {
                             "assignments" => {
                               "a" => "1",
                               "b" => "2",
                               "c" => "3",
                             },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables.keys).to contain_exactly("a", "b", "c")
    end

    it "handles empty assignments gracefully" do
      context.set_variable("_current_node_data", { "assignments" => {} })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables).to be_empty
    end

    it "falls back to literal value when expression evaluation fails" do
      context.set_variable("_current_node_data", {
                             "assignments" => { "msg" => "this is not a valid expression" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["msg"]).to be_a(String)
    end
  end
end
