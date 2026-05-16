# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop::ResponseProcessor do
  let(:capability) { build(:capabilities_human_in_the_loop_standalone) }
  let(:state) do
    Capabilities::HumanInTheLoop::ToolCallState.build(
      prompt_text: "Need one quick clarification.",
      raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"], label: "Color" }],
      capability:,
    )
  end

  it "returns validation errors when no answers are provided" do
    result = described_class.new(state, {}).call

    expect(result.success?).to be(false)
    expect(result.errors["question_1"]).to eq("Choose an option or write a custom answer.")
    expect(result.state).to be(state)
  end

  it "accepts ActionController parameters and marks the state as answered" do
    result = described_class.new(
      state,
      ActionController::Parameters.new(
        "question_1" => {
          selected_option: "Blue",
          custom_answer: "",
        },
      ),
    ).call

    expect(result.success?).to be(true)
    expect(result.state).to be_answered
    expect(result.state.answers.dig("question_1", "answer")).to eq("Blue")
  end

  it "prefers a custom answer over the selected option" do
    result = described_class.new(
      state,
      "question_1" => {
        "selected_option" => "Red",
        "custom_answer" => "Use teal instead",
      },
    ).call

    expect(result.success?).to be(true)
    expect(result.state.answers.dig("question_1", "answer")).to eq("Use teal instead")
  end

  it "rejects options that are not part of the configured list" do
    result = described_class.new(
      state,
      "question_1" => { "selected_option" => "Purple" },
    ).call

    expect(result.success?).to be(false)
    expect(result.errors["question_1"]).to eq("Choose one of the listed options or write a custom answer.")
  end

  it "rejects custom answers that exceed the max length" do
    max_length = Capabilities::HumanInTheLoop::ToolCallState::MAX_CUSTOM_ANSWER_LENGTH

    result = described_class.new(
      state,
      "question_1" => {
        "custom_answer" => "x" * (max_length + 1),
      },
    ).call

    expect(result.success?).to be(false)
    expect(result.errors["question_1"]).to eq("Custom answers must be #{max_length} characters or fewer.")
  end

  it "treats non-hash response payloads as blank answers" do
    result = described_class.new(state, "question_1" => "Blue").call

    expect(result.success?).to be(false)
    expect(result.errors["question_1"]).to eq("Choose an option or write a custom answer.")
  end

  it "returns the stored answers when already answered" do
    answered_state = state.answered_with(
      "question_1" => {
        "selected_option" => "Blue",
        "answer" => "Blue",
      },
    )

    result = described_class.new(answered_state, "question_1" => { "selected_option" => "Red" }).call

    expect(result.success?).to be(true)
    expect(result.state.answers.dig("question_1", "answer")).to eq("Blue")
  end
end
