# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseConnectionTester do
  describe "#call" do
    it "returns a failure result with 'Unknown connector type' message" do
      tester = described_class.new({})
      result = tester.call

      expect(result.success?).to be(false)
      expect(result.message).to eq("Unknown connector type")
    end
  end

  describe "Result" do
    it "defines success?, message, and details attributes" do
      result = described_class::Result.new(success?: true, message: "OK", details: { foo: "bar" })

      expect(result.success?).to be(true)
      expect(result.message).to eq("OK")
      expect(result.details).to eq({ foo: "bar" })
    end
  end
end
