# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Limit do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns limit" do
      expect(described_class.node_type).to eq("limit")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires collection and count" do
      expect(described_class.required_field_keys).to eq(["collection", "count"])
    end
  end

  describe ".variable_schema" do
    it "declares items, count, and total outputs" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("items", "count", "total")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "takes the first N items" do
      context.set_variable("items", [1, 2, 3, 4, 5])
      context.set_variable("_current_node_data", { "collection" => "items", "count" => "3" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([1, 2, 3])
      expect(result.variables["count"]).to eq(3)
      expect(result.variables["total"]).to eq(5)
    end

    it "skips items with offset" do
      context.set_variable("items", [1, 2, 3, 4, 5])
      context.set_variable("_current_node_data", {
                             "collection" => "items",
                             "count" => "2",
                             "offset" => "2",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([3, 4])
    end

    it "returns fewer items when collection is smaller than count" do
      context.set_variable("items", [1, 2])
      context.set_variable("_current_node_data", { "collection" => "items", "count" => "10" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([1, 2])
      expect(result.variables["count"]).to eq(2)
    end

    it "returns empty when offset exceeds collection size" do
      context.set_variable("items", [1, 2])
      context.set_variable("_current_node_data", {
                             "collection" => "items",
                             "count" => "5",
                             "offset" => "10",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to be_empty
    end

    it "defaults offset to zero" do
      context.set_variable("items", [1, 2, 3])
      context.set_variable("_current_node_data", { "collection" => "items", "count" => "2" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([1, 2])
    end

    it "fails without collection" do
      context.set_variable("_current_node_data", { "count" => "5" })

      result = node.execute(context)

      expect(result).to be_failure
    end

    it "fails with negative count" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]", "count" => "-1" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("must be positive")
    end

    it "fails with non-numeric count" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]", "count" => "abc" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid count")
    end

    it "parses JSON array from string" do
      context.set_variable("_current_node_data", { "collection" => "[10, 20, 30, 40]", "count" => "2" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([10, 20])
    end

    it "falls back to comma-separated string when JSON is invalid" do
      context.set_variable("_current_node_data", { "collection" => "a, b, c, d", "count" => "2" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq(["a", "b"])
    end

    it "wraps non-array non-string values into an array" do
      context.set_variable("single", 42)
      context.set_variable("_current_node_data", { "collection" => "single", "count" => "5" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([42])
    end

    it "evaluates an expression for count" do
      context.set_variable("items", [1, 2, 3, 4, 5])
      context.set_variable("page_size", 2)
      context.set_variable("_current_node_data", { "collection" => "items", "count" => "page_size" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([1, 2])
    end

    it "evaluates an expression for offset" do
      context.set_variable("items", [1, 2, 3, 4, 5])
      context.set_variable("skip", 2)
      context.set_variable("_current_node_data", { "collection" => "items", "count" => "3", "offset" => "skip" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["items"]).to eq([3, 4, 5])
    end

    it "fails with negative offset" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]", "count" => "1", "offset" => "-1" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("must be positive")
    end

    it "fails with non-numeric offset" do
      context.set_variable("_current_node_data", { "collection" => "[1,2]", "count" => "1", "offset" => "xyz" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Invalid offset")
    end

    it "fails when collection exceeds maximum size" do
      context.set_variable("huge", Array.new(10_001, 1))
      context.set_variable("_current_node_data", { "collection" => "huge", "count" => "5" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "fails when resolved collection is not an array" do
      context.set_variable("obj", "{}")
      context.set_variable("_current_node_data", { "collection" => "obj", "count" => "5" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Collection must be an array")
    end
  end
end
