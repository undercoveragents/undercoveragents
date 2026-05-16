# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::ValueResolver do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:context) { Missions::ExecutionContext.new(mission_run: run) }
  let(:resolver) { described_class.new(context) }

  describe "#template" do
    it "interpolates string templates after coercing the input to a string" do
      context.set_variable("name", "world")

      expect(resolver.template("Hello {{name}}"))
        .to eq("Hello world")
    end
  end

  describe "#formula" do
    it "evaluates an interpolated expression" do
      context.set_variable("x", 21)

      expect(resolver.formula("{{x}} * 2")).to eq(42)
    end
  end

  describe "#formula!" do
    it "evaluates an interpolated expression and raises through the context on failure" do
      context.set_variable("x", 7)

      expect(resolver.formula!("{{x}} * 3")).to eq(21)
    end
  end

  describe "#integer" do
    it "returns the provided default when the value is blank" do
      expect(resolver.integer(nil, label: "count", default: 5)).to eq(5)
    end

    it "returns nil when the value is blank and no default is provided" do
      expect(resolver.integer("", label: "count")).to be_nil
    end

    it "parses a resolved integer value" do
      context.set_variable("count", 3)

      expect(resolver.integer("{{count}}", label: "count", minimum: 1)).to eq(3)
    end

    it "raises when the resolved integer is below the minimum" do
      context.set_variable("count", 0)

      expect { resolver.integer("{{count}}", label: "count", minimum: 1) }
        .to raise_error(Missions::ExecutionError, "Count must be at least 1")
    end

    it "raises for invalid integer input" do
      expect { resolver.integer("abc", label: "count") }
        .to raise_error(Missions::ExecutionError, "Invalid count: abc")
    end
  end
end
