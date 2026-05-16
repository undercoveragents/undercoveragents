# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop::ToolCallExtension do
  let(:agent) { create(:agent) }
  let(:user) { create(:user) }
  let(:chat) { create(:chat, :user_context, user:, agent:) }
  let(:assistant_message) { create(:message, :assistant, chat:, content: "Need one more detail.") }
  let(:state) do
    Capabilities::HumanInTheLoop::ToolCallState.build(
      prompt_text: "Need one quick clarification.",
      raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"] }],
      capability: build(:capabilities_human_in_the_loop_standalone),
    ).answered_with("question_1" => { "answer" => "Blue", "selected_option" => "Blue" })
  end

  let!(:tool_call) do
    create(
      :tool_call,
      message: assistant_message,
      name: "ask_user_questions",
      tool_call_id: "call_hitl_llm_args",
      arguments: state.to_h,
    )
  end

  it "removes widget-only state from serialized LLM tool arguments", :aggregate_failures do
    llm_message = assistant_message.to_llm
    llm_tool_call = llm_message.tool_calls.fetch(tool_call.tool_call_id)

    expect(llm_tool_call.arguments).to include(
      "prompt" => "Need one quick clarification.",
      "questions" => tool_call.arguments["questions"],
    )
    expect(llm_tool_call.arguments).not_to have_key("status")
    expect(llm_tool_call.arguments).not_to have_key("answers")
    expect(llm_tool_call.arguments).not_to have_key("answered_at")
  end

  it "returns raw arguments for non-HITL tool calls" do
    generic_tool_call = build(:tool_call, name: "different_tool", arguments: { "status" => "pending" })

    expect(generic_tool_call.arguments_for_llm).to eq({ "status" => "pending" })
  end

  it "ignores LLM messages that do not expose tool calls" do
    expect do
      assistant_message.send(:sanitize_tool_call_arguments_for_llm!, Object.new)
    end.not_to raise_error
  end

  it "ignores tool call records without an LLM argument override" do
    allow(assistant_message).to receive(:tool_calls).and_return([Object.new])

    expect do
      assistant_message.send(:sanitize_tool_call_arguments_for_llm!, Struct.new(:tool_calls).new({}))
    end.not_to raise_error
  end

  it "ignores missing serialized tool call entries" do
    expect do
      assistant_message.send(:sanitize_tool_call_arguments_for_llm!, Struct.new(:tool_calls).new(nil))
    end.not_to raise_error
  end
end
