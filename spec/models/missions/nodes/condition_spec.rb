# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Condition do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns condition" do
      expect(described_class.node_type).to eq("condition")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires expression" do
      expect(described_class.required_field_keys).to eq(["expression"])
    end
  end

  describe ".variable_schema" do
    it "declares result output" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("result")
    end
  end

  describe ".default_output_ports" do
    it "has true and false ports" do
      expect(described_class.default_output_ports).to eq([
                                                           { key: "true", label: "True" },
                                                           { key: "false", label: "False" },
                                                         ])
    end
  end

  describe ".extract_variables" do
    it "extracts expression variables" do
      variables = []
      seen = Set.new
      data = { "expression" => "{{score}} > 0.8" }

      described_class.extract_variables(data, "Cond", variables, seen)

      expect(variables.pluck(:key)).to include("score")
    end
  end

  describe "#execute" do
    it "routes to true port when expression is truthy" do
      context.set_variable("score", 0.9)
      context.set_variable("_current_node_data", { "expression" => "score > 0.5" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("true")
      expect(result.variables["result"]).to be(true)
    end

    it "routes to false port when expression is falsy" do
      context.set_variable("score", 0.3)
      context.set_variable("_current_node_data", { "expression" => "score > 0.5" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("false")
      expect(result.variables["result"]).to be(false)
    end

    it "supports string comparison" do
      context.set_variable("status", "approved")
      context.set_variable("_current_node_data", { "expression" => "status == 'approved'" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("true")
    end

    it "supports direct string comparison against node-scoped llm output" do
      context.set_node_variables("llm", { "response" => "true" })
      context.set_variable("_current_node_data", { "expression" => "llm.response == 'true'" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("true")
      expect(result.variables["result"]).to be(true)
    end

    it "re-parses interpolated string operands as formula text" do
      context.set_node_variables("llm", { "response" => "true" })
      context.set_variable("_current_node_data", { "expression" => "{{llm.response}} == 'true'" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("false")
      expect(result.variables["result"]).to be(false)
    end

    it "supports variable interpolation" do
      context.set_variable("val", 10)
      context.set_variable("_current_node_data", { "expression" => "{{val}} > 5" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("true")
    end

    it "fails when no expression is configured" do
      context.set_variable("_current_node_data", { "expression" => "" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no expression")
    end

    it "fails when expression cannot be evaluated" do
      context.set_variable("_current_node_data", { "expression" => "undefined_var > 5" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Could not evaluate")
    end

    it "reads from condition key as fallback" do
      context.set_variable("x", 1)
      context.set_variable("_current_node_data", { "condition" => "x == 1" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("true")
    end
  end
end
