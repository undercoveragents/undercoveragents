# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::VariableSchema do
  describe Missions::VariableSchema::Variable do
    it "has sensible defaults" do
      var = described_class.new(name: "foo")
      expect(var.name).to eq("foo")
      expect(var.type).to eq(:any)
      expect(var.description).to eq("")
      expect(var.port).to be_nil
    end

    it "coerces name to string and type to symbol" do
      var = described_class.new(name: :bar, type: "string", description: "desc")
      expect(var.name).to eq("bar")
      expect(var.type).to eq(:string)
      expect(var.description).to eq("desc")
    end

    it "accepts an optional port" do
      var = described_class.new(name: "item", port: "loop")
      expect(var.port).to eq("loop")
    end

    it "coerces port to string" do
      var = described_class.new(name: "item", port: :loop)
      expect(var.port).to eq("loop")
    end
  end

  describe "#initialize" do
    it "accepts Variable instances" do
      var = Missions::VariableSchema::Variable.new(name: "x")
      schema = described_class.new(inputs: [var], outputs: [var])
      expect(schema.inputs).to eq([var])
      expect(schema.outputs).to eq([var])
    end

    it "coerces hashes to Variable instances" do
      schema = described_class.new(
        inputs: [{ name: "a", type: :string, description: "input a" }],
        outputs: [{ name: "b", type: :number }],
      )
      expect(schema.inputs.first).to be_a(Missions::VariableSchema::Variable)
      expect(schema.inputs.first.name).to eq("a")
      expect(schema.outputs.first.type).to eq(:number)
    end

    it "defaults to empty arrays" do
      schema = described_class.new
      expect(schema.inputs).to eq([])
      expect(schema.outputs).to eq([])
    end

    it "freezes inputs and outputs" do
      schema = described_class.new(inputs: [{ name: "x" }])
      expect(schema.inputs).to be_frozen
      expect(schema.outputs).to be_frozen
    end
  end

  describe "#input_names / #output_names" do
    it "returns arrays of name strings" do
      schema = described_class.new(
        inputs: [{ name: "a" }, { name: "b" }],
        outputs: [{ name: "c" }],
      )
      expect(schema.input_names).to eq(["a", "b"])
      expect(schema.output_names).to eq(["c"])
    end
  end

  describe "#outputs_for_port" do
    it "returns all outputs when port is nil" do
      schema = described_class.new(
        outputs: [
          { name: "item", port: "loop" },
          { name: "results", port: "done" },
          { name: "global" },
        ],
      )
      expect(schema.outputs_for_port(nil).map(&:name)).to eq(["item", "results", "global"])
    end

    it "returns only matching port and portless variables" do
      schema = described_class.new(
        outputs: [
          { name: "item", port: "loop" },
          { name: "results", port: "done" },
          { name: "global" },
        ],
      )
      loop_outputs = schema.outputs_for_port("loop")
      expect(loop_outputs.map(&:name)).to contain_exactly("item", "global")

      done_outputs = schema.outputs_for_port("done")
      expect(done_outputs.map(&:name)).to contain_exactly("results", "global")
    end
  end

  describe "#to_h" do
    it "returns a serializable hash representation" do
      schema = described_class.new(
        inputs: [{ name: "x", type: :string, description: "input" }],
        outputs: [{ name: "y", type: :number, description: "output" }],
      )
      h = schema.to_h
      expect(h[:inputs]).to eq([{ name: "x", type: :string, description: "input" }])
      expect(h[:outputs]).to eq([{ name: "y", type: :number, description: "output" }])
    end

    it "includes port in output when set" do
      schema = described_class.new(
        outputs: [{ name: "item", type: :any, description: "Current item", port: "loop" }],
      )
      h = schema.to_h
      expect(h[:outputs].first[:port]).to eq("loop")
    end

    it "omits port key when not set" do
      schema = described_class.new(
        outputs: [{ name: "response", type: :string, description: "LLM output" }],
      )
      h = schema.to_h
      expect(h[:outputs].first).not_to have_key(:port)
    end
  end
end
