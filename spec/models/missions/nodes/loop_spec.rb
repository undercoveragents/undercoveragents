# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Loop do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns loop" do
      expect(described_class.node_type).to eq("loop")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".variable_schema" do
    it "declares iteration and completed outputs" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("iteration", "completed")
    end
  end

  describe ".default_output_ports" do
    it "has loop and done ports" do
      expect(described_class.default_output_ports).to eq([
                                                           { key: "loop", label: "Loop Body" },
                                                           { key: "done", label: "Completed" },
                                                         ])
    end
  end

  describe ".extract_variables" do
    it "extracts expression variables from condition" do
      variables = []
      seen = Set.new
      data = { "condition" => "{{counter}} < 10" }

      described_class.extract_variables(data, "Loop", variables, seen)

      expect(variables.pluck(:key)).to include("counter")
    end
  end

  describe "#execute" do
    it "continues loop on first iteration with true condition" do
      context.set_variable("counter", 0)
      context.set_variable("_current_node_data", {
                             "condition" => "counter < 5",
                             "max_iterations" => 10,
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
      expect(result.variables["iteration"]).to eq(0)
    end

    it "exits loop when condition is false" do
      context.set_variable("counter", 5)
      context.set_variable("_loop_iteration", 5)
      context.set_variable("_current_node_data", {
                             "condition" => "counter < 5",
                             "max_iterations" => 10,
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("done")
      expect(result.variables["completed"]).to be(true)
    end

    it "exits loop when max iterations reached" do
      context.set_variable("_loop_iteration", 10)
      context.set_variable("_current_node_data", {
                             "condition" => "true",
                             "max_iterations" => 10,
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("done")
      expect(result.variables["completed"]).to be(true)
    end

    it "clamps max_iterations to MAX_ITERATIONS" do
      context.set_variable("_current_node_data", {
                             "max_iterations" => 999_999,
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
    end

    it "loops without condition until max iterations" do
      context.set_variable("_current_node_data", { "max_iterations" => 5 })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
      expect(result.variables["iteration"]).to eq(0)
    end

    it "exits loop when condition is unevaluable" do
      context.set_variable("_current_node_data", {
                             "condition" => "undefined_var < 5",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("done")
      expect(result.output).to include("could not be evaluated")
    end

    it "reads condition from expression key as fallback" do
      context.set_variable("x", 1)
      context.set_variable("_current_node_data", { "expression" => "x < 5" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
    end

    it "increments _loop_iteration in context" do
      context.set_variable("_current_node_data", { "max_iterations" => 5 })

      node.execute(context)

      expect(context.get_variable("_loop_iteration")).to eq(1)
    end
  end
end
