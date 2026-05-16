# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Switch do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns switch" do
      expect(described_class.node_type).to eq("switch")
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
    it "declares value and matched outputs" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("value", "matched")
    end
  end

  describe ".default_output_ports" do
    it "has a default port" do
      expect(described_class.default_output_ports).to eq([
                                                           { key: "default", label: "Default" },
                                                         ])
    end

    it "ignores non-hash JSON case data when deriving ports" do
      expect(described_class.output_ports_for("cases" => "[]")).to eq([{ key: "default", label: "Default" }])
    end
  end

  describe ".extract_variables" do
    it "extracts template variables from expression" do
      variables = []
      seen = Set.new
      data = { "expression" => "{{category}}" }

      described_class.extract_variables(data, "Switch", variables, seen)

      expect(variables.pluck(:key)).to include("category")
    end
  end

  describe "#execute" do
    it "routes to matching case port" do
      context.set_variable("category", "billing")
      context.set_variable("_current_node_data", {
                             "expression" => "{{category}}",
                             "cases" => { "technical" => "technical", "billing" => "billing" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("billing")
      expect(result.variables["value"]).to eq("billing")
      expect(result.variables["matched"]).to be(true)
    end

    it "routes to default when no case matches" do
      context.set_variable("category", "unknown")
      context.set_variable("_current_node_data", {
                             "expression" => "{{category}}",
                             "cases" => { "technical" => "technical", "billing" => "billing" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("default")
      expect(result.variables["matched"]).to be(false)
    end

    it "fails when no expression is configured" do
      context.set_variable("_current_node_data", {
                             "expression" => "",
                             "cases" => {},
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no expression")
    end

    it "handles empty cases gracefully" do
      context.set_variable("val", "test")
      context.set_variable("_current_node_data", {
                             "expression" => "{{val}}",
                             "cases" => {},
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("default")
    end

    it "compares values as strings" do
      context.set_variable("num", 42)
      context.set_variable("_current_node_data", {
                             "expression" => "{{num}}",
                             "cases" => { "answer" => "42" },
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("answer")
    end
  end
end
