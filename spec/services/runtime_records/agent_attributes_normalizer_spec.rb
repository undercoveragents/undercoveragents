# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeRecords::AgentAttributesNormalizer do
  let(:operation) { create(:operation) }
  let(:agent) { create(:agent, operation:, model_id: "gpt-4.1", thinking_effort: "low", thinking_budget: 256) }

  describe ".call" do
    it "leaves unrelated updates unchanged" do
      attributes = described_class.call(record: agent, attributes: { name: "Renamed" })

      expect(attributes).to eq({ "name" => "Renamed" })
    end

    it "leaves explicit reasoning effort unchanged" do
      attributes = described_class.call(record: agent, attributes: { thinking_effort: "medium" })

      expect(attributes).to eq({ "thinking_effort" => "medium" })
    end

    it "leaves blank reasoning effort unchanged for non-DeepSeek agents" do
      attributes = described_class.call(record: agent, attributes: { thinking_effort: nil, thinking_budget: nil })

      expect(attributes).to eq({ "thinking_effort" => nil, "thinking_budget" => nil })
    end

    it "normalizes blank reasoning effort to none for DeepSeek agents" do
      create(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])
      agent.update!(model_id: "deepseek-v4-flash")

      attributes = described_class.call(record: agent, attributes: { thinking_effort: nil, thinking_budget: nil })

      expect(attributes).to eq({ "thinking_effort" => "none", "thinking_budget" => nil })
    end

    it "uses a pending model change when detecting DeepSeek agents" do
      create(:model, model_id: "deepseek-chat", provider: "deepseek", capabilities: ["reasoning"])

      attributes = described_class.call(record: agent, attributes: { model_id: "deepseek-chat", thinking_effort: nil })

      expect(attributes).to eq({ "model_id" => "deepseek-chat", "thinking_effort" => "none", "thinking_budget" => nil })
    end

    it "clears the reasoning budget whenever reasoning is explicitly disabled" do
      attributes = described_class.call(record: agent, attributes: { thinking_effort: "none", thinking_budget: 512 })

      expect(attributes).to eq({ "thinking_effort" => "none", "thinking_budget" => nil })
    end
  end
end
