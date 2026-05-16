# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HumanInTheLoopToolCalls", :unauthenticated do
  let(:user) { create(:user) }
  let(:agent) { create(:agent) }
  let(:chat) { create(:chat, :user_context, user:, agent:) }
  let(:assistant_message) { create(:message, :assistant, chat:, content: nil) }
  let(:state) do
    Capabilities::HumanInTheLoop::ToolCallState.build(
      prompt_text: "Need one quick clarification.",
      raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"], label: "Color" }],
      capability: build(:capabilities_human_in_the_loop_standalone),
    )
  end
  let(:tool_call) do
    create(
      :tool_call,
      message: assistant_message,
      name: "ask_user_questions",
      display_name: "Ask User Questions",
      icon: "fa-solid fa-circle-question",
      arguments: state.to_h,
    )
  end
  let(:red_answer_params) do
    {
      responses: {
        "question_1" => {
          selected_option: "Red",
        },
      },
    }
  end

  def expect_resume_job_with(chat, fragment)
    expect(ChatResponseJob).to have_received(:perform_later).with(
      chat.id,
      include(fragment),
      [],
      tenant_id: chat.send(:response_job_tenant_id),
    )
  end

  before do
    sign_in(user)
    allow(ChatResponseJob).to receive(:perform_later)
    allow_any_instance_of(Chat).to receive(:broadcast_status_update) # rubocop:disable RSpec/AnyInstance
  end

  describe "POST /human_in_the_loop/tool_calls/:id/submit" do
    it "marks the tool call as answered and resumes the chat", :aggregate_failures do
      post submit_human_in_the_loop_tool_call_path(tool_call), params: red_answer_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Answers Submitted")
      expect(tool_call.reload.arguments.dig("answers", "question_1", "answer")).to eq("Red")
      expect(tool_call.arguments["status"]).to eq("answered")
      expect(chat.reload).to be_streaming
      expect_resume_job_with(chat, "Clarification answers:")
      expect_resume_job_with(chat, "Clarification context: Need one quick clarification.")
      expect_resume_job_with(chat, "Answer: Red")
    end

    it "returns validation feedback when the user submits nothing" do
      post submit_human_in_the_loop_tool_call_path(tool_call), params: {}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Choose an option or write a custom answer.")
      expect(tool_call.reload.arguments["status"]).to eq("pending")
    end

    it "is idempotent once the tool call has already been answered" do
      tool_call.update!(arguments: state.answered_with("question_1" => { "answer" => "Blue" }).to_h)

      post submit_human_in_the_loop_tool_call_path(tool_call), params: red_answer_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Answers Submitted")
      expect(ChatResponseJob).not_to have_received(:perform_later)
      expect(tool_call.reload.arguments.dig("answers", "question_1", "answer")).to eq("Blue")
    end

    it "keeps the tool call retryable when resume dispatch fails", :aggregate_failures do
      failing_service = instance_double(Capabilities::HumanInTheLoop::ChatResumeService)
      succeeding_service = instance_double(Capabilities::HumanInTheLoop::ChatResumeService, call: nil)
      allow(Capabilities::HumanInTheLoop::ChatResumeService)
        .to receive(:new)
        .and_return(failing_service, succeeding_service)
      allow(failing_service).to receive(:call).and_raise(StandardError, "resume failed")

      post submit_human_in_the_loop_tool_call_path(tool_call), params: red_answer_params

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Could not submit your answers. Please try again.")
      expect(tool_call.reload.arguments["status"]).to eq("pending")
      expect(tool_call.arguments["answers"]).to eq({})

      post submit_human_in_the_loop_tool_call_path(tool_call), params: red_answer_params

      expect(response).to have_http_status(:ok)
      expect(tool_call.reload.arguments["status"]).to eq("answered")
      expect(tool_call.arguments.dig("answers", "question_1", "answer")).to eq("Red")
    end

    it "returns not found for a different user" do
      sign_in(create(:user))

      post submit_human_in_the_loop_tool_call_path(tool_call), params: red_answer_params

      expect(response).to have_http_status(:not_found)
    end
  end
end
