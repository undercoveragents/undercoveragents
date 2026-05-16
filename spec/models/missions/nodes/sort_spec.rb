# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Sort do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns sort" do
      expect(described_class.node_type).to eq("sort")
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
    it "declares sorted and count outputs" do
      schema = described_class.variable_schema

      expect(schema.outputs.map(&:name)).to include("sorted", "count")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "sorts numbers ascending by default" do
      context.set_variable("nums", [3, 1, 4, 1, 5])
      context.set_variable("_current_node_data", { "collection" => "nums" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq([1, 1, 3, 4, 5])
    end

    it "sorts numbers descending" do
      context.set_variable("nums", [3, 1, 4])
      context.set_variable("_current_node_data", { "collection" => "nums", "direction" => "desc" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq([4, 3, 1])
    end

    it "sorts strings case-insensitively" do
      context.set_variable("words", ["Banana", "apple", "Cherry"])
      context.set_variable("_current_node_data", { "collection" => "words" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq(["apple", "Banana", "Cherry"])
    end

    it "sorts objects by field" do
      context.set_variable("people", [
                             { "name" => "Charlie" },
                             { "name" => "Alice" },
                             { "name" => "Bob" },
                           ],)
      context.set_variable("_current_node_data", { "collection" => "people", "field" => "name" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"].pluck("name")).to eq(["Alice", "Bob", "Charlie"])
    end

    it "sorts objects by numeric field descending" do
      context.set_variable("items", [
                             { "score" => 5 },
                             { "score" => 10 },
                             { "score" => 1 },
                           ],)
      context.set_variable("_current_node_data", {
                             "collection" => "items",
                             "field" => "score",
                             "direction" => "desc",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"].pluck("score")).to eq([10, 5, 1])
    end

    it "handles nil values in sort" do
      context.set_variable("items", [3, nil, 1])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["count"]).to eq(3)
    end

    it "fails without collection" do
      context.set_variable("_current_node_data", {})

      result = node.execute(context)

      expect(result).to be_failure
    end

    it "parses JSON array from string" do
      context.set_variable("_current_node_data", { "collection" => "[3, 1, 2]" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq([1, 2, 3])
    end

    it "falls back to comma-separated string when JSON is invalid" do
      context.set_variable("_current_node_data", { "collection" => "c, a, b" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq(["a", "b", "c"])
    end

    it "wraps non-array non-string values into an array" do
      context.set_variable("single", 42)
      context.set_variable("_current_node_data", { "collection" => "single" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq([42])
    end

    it "sorts non-hash items by value when field is specified" do
      context.set_variable("items", [3, 1, 2])
      context.set_variable("_current_node_data", { "collection" => "items", "field" => "name" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"]).to eq([1, 2, 3])
    end

    it "sorts objects with symbol keys by field" do
      context.set_variable("items", [{ name: "Charlie" }, { name: "Alice" }])
      context.set_variable("_current_node_data", { "collection" => "items", "field" => "name" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["sorted"].first[:name]).to eq("Alice")
    end

    it "handles boolean values via sort_key_value else branch" do
      context.set_variable("items", [true, false])
      context.set_variable("_current_node_data", { "collection" => "items" })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["count"]).to eq(2)
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
  end
end
