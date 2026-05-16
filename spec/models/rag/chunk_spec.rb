# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::Chunk do
  describe ".new" do
    it "creates with required content" do
      chunk = described_class.new(content: "hello")

      expect(chunk.content).to eq("hello")
      expect(chunk.position).to eq(0)
      expect(chunk.metadata).to eq({})
      expect(chunk.embedding).to be_nil
    end

    it "creates with all attributes" do
      chunk = described_class.new(content: "text", position: 3, metadata: { "key" => "val" }, embedding: [0.1, 0.2])

      expect(chunk.position).to eq(3)
      expect(chunk.metadata).to eq({ "key" => "val" })
      expect(chunk.embedding).to eq([0.1, 0.2])
    end
  end

  describe "#with_embedding" do
    it "returns a new chunk with the given embedding" do
      chunk = described_class.new(content: "hello")
      updated = chunk.with_embedding([0.5, 0.6])

      expect(updated.embedding).to eq([0.5, 0.6])
      expect(updated.content).to eq("hello")
      expect(chunk.embedding).to be_nil
    end
  end

  describe "#to_h" do
    it "returns a hash with all attributes" do
      chunk = described_class.new(content: "text", position: 1, metadata: { "k" => "v" }, embedding: [0.1])

      expect(chunk.to_h).to eq({ content: "text", position: 1, metadata: { "k" => "v" }, embedding: [0.1] })
    end
  end
end
