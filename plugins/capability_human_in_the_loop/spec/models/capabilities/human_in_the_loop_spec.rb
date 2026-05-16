# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop do
  let(:agent) { create(:agent) }
  let(:user) { create(:user) }

  describe ".permitted_params" do
    it "permits the capability limits only" do
      raw = ActionController::Parameters.new(
        max_questions_per_call: "4",
        max_options_per_question: "5",
        ignored: "value",
      )

      permitted = described_class.permitted_params(raw)

      expect(permitted.to_h.keys).to contain_exactly("max_questions_per_call", "max_options_per_question")
      expect(permitted[:ignored]).to be_nil
    end
  end

  describe "defaults and validations" do
    subject(:config) { build(:capabilities_human_in_the_loop_standalone) }

    it "exposes the expected metadata" do
      expect(described_class.key).to eq("human_in_the_loop")
      expect(described_class.label).to eq("Human in the Loop")
      expect(described_class.icon).to eq("fa-solid fa-circle-question")
    end

    it "uses compact defaults" do
      expect(config.max_questions_per_call).to eq(3)
      expect(config.max_options_per_question).to eq(6)
    end

    it "rejects values above the hard limits" do
      config.max_questions_per_call = 7
      config.max_options_per_question = 9

      expect(config).not_to be_valid
      expect(config.errors[:max_questions_per_call]).to be_present
      expect(config.errors[:max_options_per_question]).to be_present
    end
  end

  describe "runtime integration" do
    subject(:config) { build(:capabilities_human_in_the_loop_standalone) }

    it "returns no tools without a user-backed chat" do
      expect(config.tools_for(agent:, parent_chat: nil)).to eq([])

      chat_without_user = instance_double(Chat, user: nil)
      expect(config.tools_for(agent:, parent_chat: chat_without_user)).to eq([])
    end

    it "returns the question tool when a user-backed chat is present" do
      chat = create(:chat, :user_context, user:, agent:)

      tools = config.tools_for(agent:, parent_chat: chat)

      expect(tools.map(&:name)).to eq(["ask_user_questions"])
    end

    it "adds guidance to the system prompt only when a user is present", :aggregate_failures do
      expect(config.system_prompt_addition_for(agent:, user: nil)).to be_nil

      prompt = config.system_prompt_addition_for(agent:, user:)
      expect(prompt).to include("ask_user_questions")
      expect(prompt).to include("3 questions")
      expect(prompt).to include("6 answer options")
      expect(prompt).to include("array of objects")
      expect(prompt).to include("Do not collapse")
      expect(prompt).to include("keep only the best 6")
      expect(prompt).to include("starts with `Clarification answers:`")
      expect(prompt).to include("call `ask_user_questions` again")
      expect(prompt).to include("Never ask a blocking clarification in plain assistant text")
    end

    it "summarizes the configured limits" do
      expect(config.summary).to eq("3 questions max · 6 options/question")
    end
  end
end
