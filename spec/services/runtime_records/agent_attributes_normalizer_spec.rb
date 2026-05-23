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

    it "leaves blank reasoning effort unchanged for DeepSeek agents" do
      create(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])
      agent.update!(model_id: "deepseek-v4-flash")

      attributes = described_class.call(record: agent, attributes: { thinking_effort: nil, thinking_budget: nil })

      expect(attributes).to eq({ "thinking_effort" => nil, "thinking_budget" => nil })
    end

    it "clears the reasoning budget whenever reasoning is explicitly disabled" do
      attributes = described_class.call(record: agent, attributes: { thinking_effort: "none", thinking_budget: 512 })

      expect(attributes).to eq({ "thinking_effort" => "none", "thinking_budget" => nil })
    end

    it "keeps only user-assignable runtime tool keys for user agents" do
      BuiltinTools::Registrations.register_all!

      attributes = described_class.call(
        record: agent,
        attributes: { runtime_tool_keys: ["web.web_search", "mission_designer.read_flow"] },
      )

      expect(attributes).to eq({ "runtime_tool_keys" => ["web.web_search"] })
    end

    it "does not update runtime tool keys for builtin agents" do
      builtin_agent = build(:agent, builtin: true)

      attributes = described_class.call(
        record: builtin_agent,
        attributes: { runtime_tool_keys: ["web.web_search"] },
      )

      expect(attributes).to eq({})
    end
  end
end
