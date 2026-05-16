# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::Filter do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  def execute_filter(context, node, collection_name:, collection:, expression:)
    context.set_variable(collection_name, collection)
    context.set_variable("_current_node_data", { "collection" => collection_name, "expression" => expression })
    node.execute(context)
  end

  describe ".node_type" do
    it "returns filter" do
      expect(described_class.node_type).to eq("filter")
    end
  end

  describe ".node_category" do
    it "is control" do
      expect(described_class.node_category).to eq(:control)
    end
  end

  describe ".required_field_keys" do
    it "requires collection and expression" do
      expect(described_class.required_field_keys).to eq(["collection", "expression"])
    end
  end

  describe ".variable_schema" do
    it "declares matched and rejected variables" do
      schema = described_class.variable_schema
      names = schema.outputs.map(&:name)

      expect(names).to include("matches", "rejects")
    end
  end

  describe "#output_ports" do
    it "has match and no_match ports" do
      expect(node.output_ports).to eq([
                                        { key: "match", label: "Matches" },
                                        { key: "no_match", label: "No Match" },
                                      ])
    end
  end

  describe "#execute" do
    it "filters a numeric array" do
      context.set_variable("numbers", [1, 2, 3, 4, 5])
      context.set_variable("_current_node_data", {
                             "collection" => "numbers",
                             "expression" => "item > 3",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("match")
      expect(result.variables["matches"]).to eq([4, 5])
      expect(result.variables["rejects"]).to eq([1, 2, 3])
    end

    it "includes match and total counts in filter output" do
      context.set_variable("numbers", [1, 2, 3, 4, 5])
      context.set_variable("_current_node_data", {
                             "collection" => "numbers",
                             "expression" => "item > 3",
                           })

      result = node.execute(context)

      expect(result.variables["match_count"]).to eq(2)
      expect(result.variables["total_count"]).to eq(5)
    end

    it "routes to no_match when nothing matches" do
      context.set_variable("numbers", [1, 2, 3])
      context.set_variable("_current_node_data", {
                             "collection" => "numbers",
                             "expression" => "item > 10",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.next_port).to eq("no_match")
      expect(result.variables["matches"]).to eq([])
    end

    it "filters hash collections with dot notation on item fields" do
      result = execute_filter(
        context,
        node,
        collection_name: "posts",
        collection: [{ "title" => "short" }, { "title" => "this title should match" }],
        expression: "LENGTH(item.title) > 10",
      )

      expect(result).to be_success
      expect(result.next_port).to eq("match")
      expect(result.variables["match_count"]).to eq(1)
      expect(result.variables["matches"]).to eq(
        [
          { "title" => "this title should match" },
        ],
      )
    end

    it "fails with no collection" do
      context.set_variable("_current_node_data", {
                             "collection" => "",
                             "expression" => "item > 0",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No collection")
    end

    it "raises when the collection variable is not defined" do
      context.set_variable("_current_node_data", {
                             "collection" => "remove_duplicates.result",
                             "expression" => "item > 0",
                           })

      expect { node.execute(context) }
        .to raise_error(Missions::ExecutionError, /remove_duplicates\.result/)
    end

    it "fails with no expression" do
      context.set_variable("_current_node_data", {
                             "collection" => "[1,2,3]",
                             "expression" => "",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No filter expression")
    end

    it "parses JSON array from string" do
      context.set_variable("_current_node_data", {
                             "collection" => "[10, 20, 30]",
                             "expression" => "item > 15",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["matches"]).to eq([20, 30])
    end

    it "parses comma-separated values as collection" do
      context.set_variable("_current_node_data", {
                             "collection" => "apple, banana, cherry",
                             "expression" => "item != 'banana'",
                           })

      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["total_count"]).to eq(3)
    end

    it "wraps non-array non-string collection values" do
      context.set_variable("single_item", 42)
      context.set_variable("_current_node_data", {
                             "collection" => "single_item",
                             "expression" => "item == 42",
                           })

      result = node.execute(context)

      expect(result).to be_success
    end

    it "fails when collection exceeds maximum size" do
      oversized = Array.new(10_001, 1)
      context.set_variable("big", oversized)
      context.set_variable("_current_node_data", {
                             "collection" => "big",
                             "expression" => "item > 0",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("exceeds maximum")
    end

    it "fails when resolved collection is not an array" do
      context.set_variable("obj", "{}")
      context.set_variable("_current_node_data", {
                             "collection" => "obj",
                             "expression" => "item > 0",
                           })

      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("Collection must be an array")
    end

    it "restores the previous item variable after filtering" do
      context.set_runtime_variable("item", "original_value")
      context.set_variable("numbers", [1, 2, 3])
      context.set_variable("_current_node_data", {
                             "collection" => "numbers",
                             "expression" => "item > 1",
                           })

      node.execute(context)

      expect(context.get_variable("item")).to eq("original_value")
    end

    it "resets item to nil when no previous item existed" do
      context.set_variable("numbers", [1, 2])
      context.set_variable("_current_node_data", {
                             "collection" => "numbers",
                             "expression" => "item > 0",
                           })

      node.execute(context)

      expect(context.get_variable("item")).to be_nil
    end
  end
end
