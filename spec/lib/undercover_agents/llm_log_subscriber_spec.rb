# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::LlmLogSubscriber do
  describe ".attach!" do
    it "is idempotent" do
      expect { described_class.attach! }.not_to raise_error
    end
  end

  describe "#log" do
    it "logs safe metadata without exception internals" do
      messages = []
      allow(Rails.logger).to receive(:debug) { |&block| messages << block.call }

      described_class.new.log("llm.test", { chat_id: 1, exception: ["RuntimeError", "boom"], empty: nil })

      expect(messages.first).to include("llm.test")
      expect(messages.first).to include('"chat_id":1')
      expect(messages.first).not_to include("RuntimeError")
      expect(messages.first).not_to include("empty")
    end
  end
end
