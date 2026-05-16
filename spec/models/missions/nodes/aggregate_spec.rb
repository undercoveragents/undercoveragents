# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Aggregate do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns aggregate" do
      expect(described_class.node_type).to eq("aggregate")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires collection and operation" do
      expect(described_class.required_field_keys).to eq(["collection", "operation"])
    end
  end

  describe ".variable_schema" do
    it "declares result and count outputs" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("result", "count")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "sums numeric values" do
      context.set_variable("numbers", [10, 20, 30])
      context.set_variable("_current_node_data", { "collection" => "numbers", "operation" => "sum" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(60)
    end

    it "counts items" do
      context.set_variable("items", ["a", "b", "c", "d"])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "count" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(4)
    end

    it "averages numeric values" do
      context.set_variable("scores", [10, 20, 30])
      context.set_variable("_current_node_data", { "collection" => "scores", "operation" => "average" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(20.0)
    end

    it "finds minimum value" do
      context.set_variable("vals", [5, 2, 8, 1])
      context.set_variable("_current_node_data", { "collection" => "vals", "operation" => "min" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(1)
    end

    it "finds maximum value" do
      context.set_variable("vals", [5, 2, 8, 1])
      context.set_variable("_current_node_data", { "collection" => "vals", "operation" => "max" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(8)
    end

    it "returns first item" do
      context.set_variable("items", ["alpha", "beta", "gamma"])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "first" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("alpha")
    end

    it "returns last item" do
      context.set_variable("items", ["alpha", "beta", "gamma"])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "last" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("gamma")
    end

    it "joins items as comma-separated string" do
      context.set_variable("items", ["a", "b", "c"])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "join" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq("a, b, c")
    end

    it "collects non-nil items" do
      context.set_variable("items", [1, nil, 3, nil, 5])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "collect" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq([1, 3, 5])
    end

    it "aggregates a field from objects" do
      context.set_variable("orders", [{ "amount" => 10 }, { "amount" => 25 }, { "amount" => 15 }])
      context.set_variable("_current_node_data", {
                             "collection" => "orders",
                             "operation" => "sum",
                             "field" => "amount",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(50)
    end

    it "returns zero average for empty numeric values" do
      context.set_variable("items", ["a", "b", "c"])
      context.set_variable("_current_node_data", { "collection" => "items", "operation" => "average" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(0)
    end

    it "fails without collection" do
      context.set_variable("_current_node_data", { "operation" => "sum" })

      result = node.execute(context)

      expect(result).to be_failure
    end

    it "fails without operation" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]" })

      result = node.execute(context)

      expect(result).to be_failure
    end

    it "fails with unknown operation" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]", "operation" => "explode" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Unknown operation")
    end

    it "parses JSON array from string" do
      context.set_variable("_current_node_data", { "collection" => "[10, 20, 30]", "operation" => "sum" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(60)
    end

    it "falls back to comma-separated string when JSON is invalid" do
      context.set_variable("_current_node_data", { "collection" => "a, b, c", "operation" => "count" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(3)
    end

    it "wraps non-array non-string values into an array" do
      context.set_variable("single_value", 42)
      context.set_variable("_current_node_data", { "collection" => "single_value", "operation" => "sum" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(42)
    end

    it "returns the item itself when extracting field from non-hash" do
      context.set_variable("items", [10, 20, 30])
      context.set_variable("_current_node_data", {
                             "collection" => "items",
                             "operation" => "sum",
                             "field" => "value",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(60)
    end

    it "extracts field via symbol key when string key is absent" do
      context.set_variable("items", [{ amount: 10 }, { amount: 20 }])
      context.set_variable("_current_node_data", {
                             "collection" => "items",
                             "operation" => "sum",
                             "field" => "amount",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["result"]).to eq(30)
    end

    describe "private helpers" do
      it "returns nil for unknown aggregate operations" do
        expect(node.send(:perform_operation, "missing", [1, 2, 3])).to be_nil
      end
    end

    it "fails when collection exceeds maximum size" do
      context.set_variable("huge", Array.new(10_001, 1))
      context.set_variable("_current_node_data", { "collection" => "huge", "operation" => "count" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "fails when resolved collection is not an array" do
      context.set_variable("obj", "{}")
      context.set_variable("_current_node_data", { "collection" => "obj", "operation" => "count" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Collection must be an array")
    end
  end
end
