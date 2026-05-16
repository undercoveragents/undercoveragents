# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Iterator do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it { expect(described_class.node_type).to eq("iterator") }
  end

  describe ".node_category" do
    it { expect(described_class.node_category).to eq(:control) }
  end

  describe ".required_field_keys" do
    it { expect(described_class.required_field_keys).to eq(["collection"]) }
  end

  describe ".variable_schema" do
    it "declares item/index/total/results outputs" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to contain_exactly("item", "index", "total", "results")
    end
  end

  describe ".input_schema" do
    it "declares collection and parallel execution config inputs" do
      expect(described_class.input_schema.pluck(:name)).to eq(["collection", "parallel", "max_parallel_branches"])
    end
  end

  describe ".default_output_ports" do
    it "has loop and done ports" do
      ports = described_class.default_output_ports
      expect(ports.pluck(:key)).to eq(["loop", "done"])
    end
  end

  describe ".extract_variables" do
    it "extracts a simple variable reference" do
      variables = []
      seen = Set.new
      described_class.extract_variables({ "collection" => "items" }, "Iterator", variables, seen)
      expect(variables.pluck(:key)).to include("items")
    end

    it "skips non-identifier expressions" do
      variables = []
      seen = Set.new
      described_class.extract_variables({ "collection" => "[1,2,3]" }, "Iterator", variables, seen)
      expect(variables).to be_empty
    end
  end

  describe "#execute" do
    it "resolves a direct JSON array expression when no variable exists" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
      expect(result.output).to eq(1)
      expect(result.variables).to include("item" => 1, "index" => 0, "total" => 2)
    end

    it "iterates over a variable containing an array" do
      context.set_variable("items", [10, 20, 30])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("loop")
      expect(result.variables).to include("item" => 10, "index" => 0, "total" => 3)
    end

    it "stores iterator metadata in context" do
      context.set_variable("items", [1, 2])
      context.set_variable("_current_node_id", "iter-1")
      context.set_variable("_current_node_data", { "collection" => "items" })

      node.execute(context)

      expect(context.iterator_state("iter-1")).to include(
        "collection" => [1, 2],
        "index" => 0,
        "total" => 2,
        "results" => [],
        "parallel" => false,
        "max_parallel_branches" => described_class::DEFAULT_MAX_PARALLEL_BRANCHES,
      )
    end

    it "stores parallel iterator metadata when configured" do
      context.set_variable("items", [1, 2, 3])
      context.set_variable("_current_node_id", "iter-1")
      context.set_variable(
        "_current_node_data",
        { "collection" => "items", "parallel" => true, "max_parallel_branches" => "8" },
      )

      node.execute(context)

      expect(context.iterator_state("iter-1")).to include(
        "parallel" => true,
        "max_parallel_branches" => 8,
      )
    end

    it "returns done port with empty results for empty collection" do
      context.set_variable("items", [])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("done")
      expect(result.variables).to include("results" => [], "total" => 0)
    end

    it "fails when the resolved collection is not an array" do
      context.set_variable("_current_node_data", { "collection" => "scalar" })
      allow(node).to receive(:resolve_collection).and_return("not-an-array")

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to eq("Iterator collection must be an array, got String")
    end

    it "fails when collection exceeds MAX_ITERATIONS" do
      large = Array.new(1001) { |i| i }
      context.set_variable("big", large)
      context.set_variable("_current_node_data", { "collection" => "big" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "parses a comma-separated string variable as array" do
      context.set_variable("csv_data", "a, b, c")
      context.set_variable("_current_node_data", { "collection" => "csv_data" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["item"]).to eq("a")
      expect(result.variables["total"]).to eq(3)
    end

    it "parses a JSON array string variable" do
      context.set_variable("json_arr", "[1, 2, 3]")
      context.set_variable("_current_node_data", { "collection" => "json_arr" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["item"]).to eq(1)
      expect(result.variables["total"]).to eq(3)
    end

    it "resolves interpolated template collection" do
      context.set_variable("source", [5, 10])
      context.set_variable("_current_node_data", { "collection" => "{{source}}" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["item"]).to eq(5)
    end

    it "raises when an interpolated collection reference stays unresolved" do
      context.set_variable("_current_node_data", { "collection" => "{{missing_collection}}" })

      expect { node.execute(context) }
        .to raise_error(
          Missions::ExecutionError,
          /Iterator collection variable '\{\{missing_collection\}\}' is not defined/,
        )
    end

    it "fails when no collection is configured" do
      context.set_variable("_current_node_data", {})

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("no collection configured")
    end

    it "falls back to expression key when collection is absent" do
      context.set_variable("_current_node_data", { "expression" => "[4,5,6]" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["item"]).to eq(4)
      expect(result.variables["total"]).to eq(3)
    end

    it "wraps a non-array value in an array" do
      context.set_variable("single", 42)
      context.set_variable("_current_node_data", { "collection" => "single" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["item"]).to eq(42)
      expect(result.variables["total"]).to eq(1)
    end
  end
end
