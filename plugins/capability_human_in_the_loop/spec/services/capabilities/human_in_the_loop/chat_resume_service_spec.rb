# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop::ChatResumeService do
  let(:user) { create(:user) }
  let(:agent) { create(:agent) }
  let(:answered_state) do
    Capabilities::HumanInTheLoop::ToolCallState.build(
      prompt_text: nil,
      raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"], label: "Color" }],
      capability: build(:capabilities_human_in_the_loop_standalone),
    ).answered_with(
      "question_1" => {
        "selected_option" => "Blue",
        "answer" => "Blue",
      },
    )
  end

  it "delegates resume dispatch to the chat" do
    chat = create(:chat, :user_context, user:, agent:)
    tool_call = create(
      :tool_call,
      message: create(:message, :assistant, chat:, content: nil),
      name: "ask_user_questions",
      display_name: "Ask User Questions",
      icon: "fa-solid fa-circle-question",
      arguments: answered_state.to_h,
    )
    allow(chat).to receive(:enqueue_response!)

    described_class.new(tool_call).call

    expect(chat).to have_received(:enqueue_response!).with(content: tool_call.human_in_the_loop_resume_message_content)
  end
end
