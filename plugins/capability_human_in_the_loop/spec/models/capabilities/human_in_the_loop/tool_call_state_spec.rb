# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::HumanInTheLoop::ToolCallState do
  let(:capability) do
    build(:capabilities_human_in_the_loop_standalone, max_questions_per_call: 2, max_options_per_question: 3)
  end
  let(:raw_questions) do
    [
      {
        prompt: "What tone should I use?",
        options: ["Formal", " Casual ", "Formal"],
        label: "Tone",
        helper_text: "Pick the closest fit.",
      },
    ]
  end

  describe ".build" do
    it "normalizes and stores the question payload" do
      state = described_class.build(
        prompt_text: "  Need one detail.  ",
        raw_questions:,
        capability:,
      )

      expect(state.prompt_text).to eq("Need one detail.")
      expect(state.questions).to eq([
                                      {
                                        "id" => "question_1",
                                        "prompt" => "What tone should I use?",
                                        "options" => ["Formal", "Casual"],
                                        "label" => "Tone",
                                        "helper_text" => "Pick the closest fit.",
                                      },
                                    ])
      expect(state).to be_pending
      expect(state.answers).to eq({})
    end

    it "parses inline string questions with embedded options" do
      state = described_class.build(
        prompt_text: "Need one detail.",
        raw_questions: [
          "Question 1: What kind of information should I look up? " \
          "Options: Customers, invoices, tracks/songs, or something else.",
        ],
        capability:,
      )

      expect(state.questions).to eq([
                                      {
                                        "id" => "question_1",
                                        "prompt" => "What kind of information should I look up?",
                                        "options" => ["Customers", "invoices", "tracks/songs"],
                                        "label" => "Q1",
                                      },
                                    ])
    end

    it "rejects tool calls that exceed the configured limit" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [
            { prompt: "A?", options: ["1"] },
            { prompt: "B?", options: ["2"] },
            { prompt: "C?", options: ["3"] },
          ],
          capability:,
        )
      end.to raise_error(ArgumentError, "Ask at most 2 questions per request.")
    end

    it "rejects an intro that exceeds the max length" do
      expect do
        described_class.build(
          prompt_text: "x" * (described_class::MAX_PROMPT_TEXT_LENGTH + 1),
          raw_questions:,
          capability:,
        )
      end.to raise_error(
        ArgumentError,
        "The request intro must be #{described_class::MAX_PROMPT_TEXT_LENGTH} characters or fewer.",
      )
    end

    it "stores a nil intro when the provided text is blank" do
      state = described_class.build(prompt_text: "   ", raw_questions:, capability:)

      expect(state.prompt_text).to be_nil
      expect(state.to_h["prompt"]).to be_nil
    end

    it "rejects a question prompt that exceeds the max length" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [{ prompt: "x" * (described_class::MAX_QUESTION_PROMPT_LENGTH + 1), options: ["Formal"] }],
          capability:,
        )
      end.to raise_error(
        ArgumentError,
        "Question 1 must be #{described_class::MAX_QUESTION_PROMPT_LENGTH} characters or fewer.",
      )
    end

    it "rejects question payloads that do not expose hash data" do
      expect do
        described_class.build(prompt_text: nil, raw_questions: [Object.new], capability:)
      end.to raise_error(ArgumentError, "Question 1 must include a prompt.")
    end

    it "rejects inline string questions without answer options" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: ["Question 1: What tone should I use?"],
          capability:,
        )
      end.to raise_error(ArgumentError, "Question 1 must include at least one answer option.")
    end

    it "rejects questions without answer options" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [{ prompt: "What tone should I use?", options: [] }],
          capability:,
        )
      end.to raise_error(ArgumentError, "Question 1 must include at least one answer option.")
    end

    it "truncates questions with too many options to the configured limit" do
      state = described_class.build(
        prompt_text: nil,
        raw_questions: [{ prompt: "What tone should I use?", options: ["Formal", "Casual", "Direct", "Playful"] }],
        capability:,
      )

      expect(state.questions.first.fetch("options")).to eq(["Formal", "Casual", "Direct"])
    end

    it "rejects options that exceed the max length" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [{
            prompt: "What tone should I use?",
            options: ["x" * (described_class::MAX_OPTION_LENGTH + 1)],
          }],
          capability:,
        )
      end.to raise_error(
        ArgumentError,
        "Question 1 options must be #{described_class::MAX_OPTION_LENGTH} characters or fewer.",
      )
    end

    it "rejects labels that exceed the max length" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [{
            prompt: "What tone should I use?",
            options: ["Formal"],
            label: "x" * (described_class::MAX_LABEL_LENGTH + 1),
          }],
          capability:,
        )
      end.to raise_error(
        ArgumentError,
        "Question 1 label must be #{described_class::MAX_LABEL_LENGTH} characters or fewer.",
      )
    end

    it "rejects helper text that exceeds the max length" do
      expect do
        described_class.build(
          prompt_text: nil,
          raw_questions: [{
            prompt: "What tone should I use?",
            options: ["Formal"],
            helper_text: "x" * (described_class::MAX_HELPER_TEXT_LENGTH + 1),
          }],
          capability:,
        )
      end.to raise_error(
        ArgumentError,
        "Question 1 helper text must be #{described_class::MAX_HELPER_TEXT_LENGTH} characters or fewer.",
      )
    end
  end

  describe "instance helpers" do
    let(:state) do
      described_class.build(
        prompt_text: "Need one quick clarification.",
        raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"], label: "Color" }],
        capability: build(:capabilities_human_in_the_loop_standalone),
      )
    end

    it "reports renderability and question metadata" do
      expect(state.renderable?).to be(true)
      expect(state.question_count).to eq(1)
      expect(state.question_ids).to eq(["question_1"])
      expect(state.answer_for("question_1")).to eq({})
    end

    it "falls back to an empty answer hash when persisted answers are malformed" do
      malformed = described_class.from_arguments(state.to_h.merge("answers" => "Blue"))

      expect(malformed.answers).to eq({})
    end

    it "falls back to pending when the persisted status is unknown" do
      malformed = described_class.from_arguments(state.to_h.merge("status" => "other"))

      expect(malformed.status).to eq("pending")
      expect(malformed).to be_pending
    end

    it "returns false for malformed persisted state" do
      malformed = described_class.from_arguments("questions" => [nil])

      expect(malformed.renderable?).to be(false)
    end

    it "coerces non-hash persisted payloads into an empty state" do
      malformed = described_class.from_arguments("invalid")

      expect(malformed.renderable?).to be(false)
      expect(malformed.answers).to eq({})
      expect(malformed.to_h).to eq(
        "questions" => [],
        "answers" => {},
        "status" => "pending",
      )
    end

    it "builds pause and resume messages from the stored state", :aggregate_failures do
      answered_state = state.answered_with(
        "question_1" => {
          "selected_option" => "Blue",
          "answer" => "Blue",
        },
      )

      expect(state.pause_message_content).to include("Wait for the user's answers before continuing.")
      expect(state.pause_message_content).to include("Which color should I use?")
      expect(state.pause_message_content).to include("Options: Red | Blue")
      expect(answered_state).to be_answered
      expect(answered_state.resume_message_content).to include("Clarification answers:")
      expect(answered_state.resume_message_content).to include("Clarification context: Need one quick clarification.")
      expect(answered_state.resume_message_content).to include("Which color should I use?")
      expect(answered_state.resume_message_content).to include("Answer: Blue")
    end

    it "omits blank prompt text and unanswered rows from generated messages", :aggregate_failures do
      promptless_state = described_class.build(
        prompt_text: nil,
        raw_questions: [{ prompt: "Which color should I use?", options: ["Red", "Blue"] }],
        capability: build(:capabilities_human_in_the_loop_standalone),
      )

      expect(promptless_state.pause_message_content).not_to include("Need one quick clarification.")
      expect(promptless_state.resume_message_content).to eq("Clarification answers:")
    end
  end
end
