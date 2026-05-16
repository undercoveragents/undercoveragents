# frozen_string_literal: true

require "rails_helper"

RSpec.describe NullByteSanitizable do
  let(:test_class) do
    Class.new do
      include NullByteSanitizable
    end
  end

  let(:instance) { test_class.new }

  describe "#sanitize_null_bytes" do
    it "removes null bytes from strings" do
      expect(instance.sanitize_null_bytes("Hello\u0000World")).to eq("HelloWorld")
    end

    it "returns nil for nil input" do
      expect(instance.sanitize_null_bytes(nil)).to be_nil
    end

    it "returns blank strings as-is" do
      expect(instance.sanitize_null_bytes("")).to eq("")
    end

    it "returns strings without null bytes unchanged" do
      expect(instance.sanitize_null_bytes("Hello World")).to eq("Hello World")
    end

    it "removes multiple null bytes" do
      expect(instance.sanitize_null_bytes("\u0000A\u0000B\u0000")).to eq("AB")
    end
  end

  describe "#deep_sanitize_null_bytes" do
    it "sanitizes strings" do
      expect(instance.deep_sanitize_null_bytes("Hello\u0000")).to eq("Hello")
    end

    it "sanitizes hash values recursively" do
      data = { "key" => "val\u0000ue", "nested" => { "inner" => "in\u0000ner" } }
      result = instance.deep_sanitize_null_bytes(data)

      expect(result).to eq({ "key" => "value", "nested" => { "inner" => "inner" } })
    end

    it "sanitizes array elements recursively" do
      data = ["Hello\u0000", { "key" => "val\u0000ue" }, ["nested\u0000"]]
      result = instance.deep_sanitize_null_bytes(data)

      expect(result).to eq(["Hello", { "key" => "value" }, ["nested"]])
    end

    it "returns non-string non-collection values unchanged" do
      expect(instance.deep_sanitize_null_bytes(42)).to eq(42)
      expect(instance.deep_sanitize_null_bytes(true)).to be(true)
      expect(instance.deep_sanitize_null_bytes(nil)).to be_nil
    end
  end
end
