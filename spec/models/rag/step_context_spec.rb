# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rag::StepContext do
  describe ".new" do
    it "creates with required run_id and flow_id" do
      ctx = described_class.new(run_id: 1, flow_id: 2)

      expect(ctx.run_id).to eq(1)
      expect(ctx.flow_id).to eq(2)
      expect(ctx.batch_number).to eq(1)
      expect(ctx.total_batches).to be_nil
      expect(ctx.metadata).to eq({})
    end

    it "creates with all optional attributes" do
      ctx = described_class.new(run_id: 5, flow_id: 7, batch_number: 3, total_batches: 10, metadata: { "key" => "val" })

      expect(ctx.batch_number).to eq(3)
      expect(ctx.total_batches).to eq(10)
      expect(ctx.metadata).to eq({ "key" => "val" })
    end
  end

  describe "#next_batch" do
    it "returns a new context with incremented batch_number" do
      ctx = described_class.new(run_id: 1, flow_id: 2, batch_number: 2)

      next_ctx = ctx.next_batch

      expect(next_ctx.batch_number).to eq(3)
      expect(next_ctx.run_id).to eq(1)
      expect(ctx.batch_number).to eq(2)
    end
  end

  describe "#to_context_hash" do
    it "returns a hash with all context values" do
      ctx = described_class.new(run_id: 1, flow_id: 2, batch_number: 1, total_batches: 5, metadata: {})

      hash = ctx.to_context_hash

      expect(hash[:run_id]).to eq(1)
      expect(hash[:flow_id]).to eq(2)
      expect(hash[:batch_number]).to eq(1)
      expect(hash[:total_batches]).to eq(5)
      expect(hash[:metadata]).to eq({})
    end
  end
end
