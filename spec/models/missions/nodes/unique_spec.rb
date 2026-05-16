# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Unique do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns unique" do
      expect(described_class.node_type).to eq("unique")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires collection" do
      expect(described_class.required_field_keys).to eq(["collection"])
    end
  end

  describe ".variable_schema" do
    it "declares unique, duplicates, and count outputs" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("unique", "duplicates", "count")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "removes duplicate values" do
      context.set_variable("items", [1, 2, 2, 3, 3, 3])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([1, 2, 3])
      expect(result.variables["duplicates"]).to eq([2, 3, 3])
      expect(result.variables["count"]).to eq(3)
    end

    it "removes duplicate strings" do
      context.set_variable("items", ["a", "b", "a", "c", "b"])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq(["a", "b", "c"])
    end

    it "deduplicates by field" do
      context.set_variable("users", [
                             { "email" => "a@test.com", "name" => "Alice" },
                             { "email" => "b@test.com", "name" => "Bob" },
                             { "email" => "a@test.com", "name" => "Alice2" },
                           ],)
      context.set_variable("_current_node_data", { "collection" => "users", "field" => "email" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"].size).to eq(2)
      expect(result.variables["duplicates"].size).to eq(1)
    end

    it "preserves order of first occurrences" do
      context.set_variable("items", [3, 1, 2, 1, 3])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([3, 1, 2])
    end

    it "returns all items when no duplicates" do
      context.set_variable("items", [1, 2, 3])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([1, 2, 3])
      expect(result.variables["duplicates"]).to be_empty
    end

    it "fails without collection" do
      context.set_variable("_current_node_data", {})

      result = node.execute(context)

      expect(result).to be_failure
    end

    it "parses JSON array from string" do
      context.set_variable("_current_node_data", { "collection" => "[1, 1, 2, 2, 3]" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([1, 2, 3])
    end

    it "parses comma-separated values from a string variable" do
      context.set_variable("csv_items", "a, b, a, c")
      context.set_variable("_current_node_data", { "collection" => "csv_items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq(["a", "b", "c"])
    end

    it "falls back to comma-separated string when JSON is invalid" do
      context.set_variable("_current_node_data", { "collection" => "a, b, a, c" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq(["a", "b", "c"])
    end

    it "wraps non-array non-string values into an array" do
      context.set_variable("single", 42)
      context.set_variable("_current_node_data", { "collection" => "single" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([42])
    end

    it "deduplicates with symbol keys when field is given" do
      context.set_variable("items", [{ name: "Alice" }, { name: "Bob" }, { name: "Alice" }])
      context.set_variable("_current_node_data", { "collection" => "items", "field" => "name" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"].size).to eq(2)
    end

    it "uses the item itself as key for non-hash items when field is given" do
      context.set_variable("items", [1, 2, 1])
      context.set_variable("_current_node_data", { "collection" => "items", "field" => "id" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["unique"]).to eq([1, 2])
    end

    it "fails when collection exceeds maximum size" do
      context.set_variable("huge", Array.new(10_001, 1))
      context.set_variable("_current_node_data", { "collection" => "huge" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "fails when resolved collection is not an array" do
      context.set_variable("obj", "{}")
      context.set_variable("_current_node_data", { "collection" => "obj" })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Collection must be an array")
    end

    it "raises when an interpolated collection reference stays unresolved" do
      context.set_variable("_current_node_data", { "collection" => "{{missing_collection}}" })

      expect { node.execute(context) }
        .to raise_error(Missions::ExecutionError, /\{\{missing_collection\}\}/)
    end
  end
end
