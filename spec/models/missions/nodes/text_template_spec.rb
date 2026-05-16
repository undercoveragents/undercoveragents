# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::Nodes::TextTemplate do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:node) { described_class.new }

  describe ".node_type" do
    it "returns text_template" do
      expect(described_class.node_type).to eq("text_template")
    end
  end

  describe ".node_category" do
    it "is node" do
      expect(described_class.node_category).to eq(:node)
    end
  end

  describe ".required_field_keys" do
    it "requires template" do
      expect(described_class.required_field_keys).to eq(["template"])
    end
  end

  describe ".variable_schema" do
    it "declares text output" do
      schema = described_class.variable_schema
      expect(schema.outputs.map(&:name)).to include("text")
    end
  end

  describe "#output_ports" do
    it "has a single default port" do
      expect(node.output_ports).to eq([{ key: "default", label: "Output" }])
    end
  end

  describe "#execute" do
    it "renders a simple template" do
      context.set_variable("_current_node_data", { "template" => "Hello, World!" })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["text"]).to eq("Hello, World!")
    end

    it "interpolates variables" do
      context.set_variable("name", "Alice")
      context.set_variable("score", 95)
      context.set_variable("_current_node_data", {
                             "template" => "Hello {{name}}, your score is {{score}}!",
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["text"]).to eq("Hello Alice, your score is 95!")
    end

    it "preserves unresolved variables" do
      context.set_variable("_current_node_data", {
                             "template" => "Hello {{unknown_var}}!",
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["text"]).to eq("Hello {{unknown_var}}!")
    end

    it "fails with blank template" do
      context.set_variable("_current_node_data", { "template" => "" })
      result = node.execute(context)

      expect(result).to be_failure
      expect(result.output).to include("No template provided")
    end

    it "handles dot-syntax variables" do
      context.set_node_variables("user", { "name" => "Bob" })
      context.set_variable("_current_node_data", {
                             "template" => "Welcome, {{user.name}}!",
                           })
      result = node.execute(context)

      expect(result).to be_success
      expect(result.variables["text"]).to eq("Welcome, Bob!")
    end
  end
end
