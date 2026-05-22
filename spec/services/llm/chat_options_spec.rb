# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::ChatOptions do
  describe ".apply_to_chat" do
    let(:chat) { instance_double(Chat) }

    before do
      allow(chat).to receive(:with_temperature)
      allow(chat).to receive(:with_thinking)
      allow(chat).to receive(:with_params)
    end

    it "applies supported temperature, thinking, and custom params" do
      model = build(:model, capabilities: ["temperature", "reasoning"])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        temperature: 0.4,
        thinking_effort: "medium",
        thinking_budget: 256,
        custom_params: '{"top_p":0.9}',
      )

      expect(chat).to have_received(:with_temperature).with(0.4)
      expect(chat).to have_received(:with_thinking).with(effort: :medium, budget: 256)
      expect(chat).to have_received(:with_params).with(top_p: 0.9)
    end

    it "skips unsupported temperature and reasoning settings" do
      model = build(:model, capabilities: [])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        temperature: 0.4,
        thinking_effort: "high",
      )

      expect(chat).not_to have_received(:with_temperature)
      expect(chat).not_to have_received(:with_thinking)
    end

    it "applies thinking when model metadata is unavailable" do
      described_class.apply_to_chat(chat:, model_id: nil, thinking_effort: "low")

      expect(chat).to have_received(:with_thinking).with(effort: :low)
    end

    it "does not call with_thinking when the UI reasoning setting is off" do
      model = build(:model, capabilities: ["reasoning"])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        thinking_effort: "none",
      )

      expect(chat).not_to have_received(:with_thinking)
    end

    it "sends an explicit DeepSeek disable toggle when the UI reasoning setting is off" do
      model = build(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        thinking_effort: "none",
      )

      expect(chat).not_to have_received(:with_thinking)
      expect(chat).to have_received(:with_params).with(thinking: { type: "disabled" })
    end

    it "merges the explicit DeepSeek disable toggle with custom params" do
      model = build(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        thinking_effort: "none",
        custom_params: { "top_p" => 0.8 },
      )

      expect(chat).to have_received(:with_params).with(top_p: 0.8, thinking: { type: "disabled" })
    end

    it "applies DeepSeek reasoning when tools are present" do
      model = build(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])

      described_class.apply_to_chat(
        chat:,
        model_id: model.model_id,
        model_record: model,
        thinking_effort: "high",
        tools_present: true,
      )

      expect(chat).to have_received(:with_thinking).with(effort: :high)
      expect(chat).not_to have_received(:with_params)
    end

    it "still applies thinking when tools are present but model metadata is unavailable" do
      described_class.apply_to_chat(
        chat:,
        model_id: nil,
        thinking_effort: "low",
        tools_present: true,
      )

      expect(chat).to have_received(:with_thinking).with(effort: :low)
    end
  end

  describe ".normalize_custom_params" do
    it "returns an empty hash for blank strings" do
      expect(described_class.normalize_custom_params("   ")).to eq({})
    end

    it "normalizes objects that respond to to_h" do
      wrapper = Struct.new(:payload) do
        def to_h
          payload
        end
      end.new({ top_p: 0.9 })

      expect(described_class.normalize_custom_params(wrapper)).to eq({ "top_p" => 0.9 })
    end

    it "returns an empty hash for unsupported objects" do
      expect(described_class.normalize_custom_params(Object.new)).to eq({})
    end

    it "raises when the payload is not a json object" do
      expect do
        described_class.normalize_custom_params('["bad"]')
      end.to raise_error(described_class::InvalidCustomParamsError, /JSON object/)
    end
  end

  describe ".thinking_options" do
    it "returns nil when the reasoning setting is off" do
      expect(described_class.thinking_options(effort: "none", budget: nil)).to be_nil
    end

    it "raises on an invalid thinking effort" do
      expect do
        described_class.thinking_options(effort: "extreme", budget: nil)
      end.to raise_error(ArgumentError, /invalid/)
    end
  end

  describe ".apply_to_chat keyword forwarding" do
    it "passes custom params as keywords to chat.with_params" do
      model = build(:model, model_id: "deepseek-v4-pro", provider: "deepseek", capabilities: ["reasoning"])
      chat = Class.new do
        attr_reader :params

        def with_temperature(*) = self
        def with_thinking(**) = self

        def with_params(**params)
          @params = params
          self
        end
      end.new

      expect do
        described_class.apply_to_chat(
          chat:,
          model_id: model.model_id,
          model_record: model,
          custom_params: { "top_p" => 0.8 },
        )
      end.not_to raise_error

      expect(chat.params).to eq(top_p: 0.8)
    end
  end
end
