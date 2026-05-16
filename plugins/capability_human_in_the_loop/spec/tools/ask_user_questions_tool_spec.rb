# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop::AskUserQuestionsTool do
  def trigger_tool_call_start(chat, tool_call_id:, tool_name:)
    Array(chat.instance_variable_get(:@_before_tool_call_execution_observers)).each do |callback|
      callback.call(Struct.new(:id, :name).new(tool_call_id, tool_name))
    end
  end

  let(:agent) { create(:agent) }
  let(:user) { create(:user) }
  let(:chat) { create(:chat, :user_context, user:, agent:) }
  let(:capability) { build(:capabilities_human_in_the_loop_standalone) }
  let(:tool) { described_class.for_agent(agent, chat:, capability:) }

  describe "#name" do
    it "uses a stable runtime name" do
      expect(tool.name).to eq("ask_user_questions")
    end
  end

  describe "#execute" do
    let(:questions) do
      [
        {
          prompt: "Which color should I use?",
          options: ["Red", "Blue"],
          label: "Color",
        },
      ]
    end
    let(:assistant_message) { create(:message, :assistant, chat:, content: nil) }
    let!(:tool_call_record) do
      create(
        :tool_call,
        message: assistant_message,
        name: "ask_user_questions",
        tool_call_id: "tool-call-123",
        arguments: {},
      )
    end

    before do
      tool
      trigger_tool_call_start(chat, tool_call_id: "tool-call-123", tool_name: tool.name)
    end

    it "stores widget state on the current tool call and halts the conversation", :aggregate_failures do
      result = tool.execute(prompt: "I need one quick clarification.", questions:)

      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(result.content).to include("Wait for the user's answers before continuing.")
      expect(tool_call_record.reload.arguments["status"]).to eq("pending")
      expect(tool_call_record.arguments["prompt"]).to eq("I need one quick clarification.")
      expect(tool_call_record.arguments.dig("questions", 0, "prompt")).to eq("Which color should I use?")
      expect(tool_call_record.display_name).to eq("Ask User Questions")
      expect(tool_call_record.icon).to eq("fa-solid fa-circle-question")
    end

    it "accepts inline string questions emitted as legacy prose" do
      result = tool.execute(
        prompt: "What would you like me to search for in the Chinook database?",
        questions: [
          "Question 1: What kind of information should I look up? Options: Customers, invoices, " \
          "tracks/songs, albums, artists, playlists, employees, genres, sales totals, or something else.",
        ],
      )

      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(tool_call_record.reload.arguments.dig("questions", 0, "prompt")).to eq(
        "What kind of information should I look up?",
      )
      expect(tool_call_record.arguments.dig("questions", 0, "options")).to eq(
        ["Customers", "invoices", "tracks/songs", "albums", "artists", "playlists"],
      )
    end

    it "returns a friendly message when no signed-in user backs the chat" do
      userless_chat = create(:chat, :user_context, user: nil, agent:)
      userless_tool = described_class.for_agent(agent, chat: userless_chat, capability:)

      expect(userless_tool.execute(prompt: nil, questions:)).to eq(
        "This tool is only available while chatting with a signed-in user.",
      )
    end

    it "returns a friendly message when no chat context is available" do
      missing_chat_tool = described_class.for_agent(agent, chat: nil, capability:)

      expect(missing_chat_tool.execute(prompt: nil, questions:)).to eq(
        "This tool is only available while chatting with a signed-in user.",
      )
    end

    it "surfaces validation errors from the question payload" do
      expect(tool.execute(prompt: nil, questions: [])).to eq(
        "Could not ask the user questions: Add at least one question.",
      )
    end

    it "returns a friendly error when the tool call record cannot be found" do
      tool_call_record.destroy!

      expect(tool.execute(prompt: nil, questions:)).to eq(
        "Could not ask the user questions: Could not locate the current tool call record.",
      )
    end

    it "handles unexpected runtime errors" do
      allow(ToolCall).to receive(:find_by).and_raise(StandardError, "boom")

      expect(tool.execute(prompt: nil, questions:)).to eq("Could not ask the user questions: boom")
    end
  end

  describe "tool call tracking" do
    it "ignores unrelated tool call start events" do
      tool

      trigger_tool_call_start(chat, tool_call_id: "other-call", tool_name: "different_tool")

      expect(tool.instance_variable_get(:@current_tool_call_id)).to be_nil
    end
  end
end
