# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    class ToolCallState
      SubmissionResult = Data.define(:success?, :state, :responses, :errors)

      MAX_PROMPT_TEXT_LENGTH = 220
      MAX_QUESTION_PROMPT_LENGTH = 220
      MAX_OPTION_LENGTH = 80
      MAX_LABEL_LENGTH = 22
      MAX_HELPER_TEXT_LENGTH = 120
      MAX_CUSTOM_ANSWER_LENGTH = 500

      class << self
        def build(prompt_text:, raw_questions:, capability:)
          normalized_questions = Capabilities::HumanInTheLoop::QuestionNormalizer.new(
            raw_questions,
            max_questions: capability.max_questions_per_call,
            max_options: capability.max_options_per_question,
          ).call

          new(
            "prompt" => normalize_prompt_text!(prompt_text),
            "questions" => normalized_questions,
            "answers" => {},
            "status" => pending_status,
          )
        end

        def from_arguments(arguments)
          new(arguments)
        end

        def pending_status
          "pending"
        end

        def answered_status
          "answered"
        end

        def valid_status?(value)
          value == pending_status || value == answered_status
        end

        private

        def normalize_prompt_text!(value)
          prompt_text = value.to_s.squish
          return nil if prompt_text.blank?

          if prompt_text.length > MAX_PROMPT_TEXT_LENGTH
            raise ArgumentError, "The request intro must be #{MAX_PROMPT_TEXT_LENGTH} characters or fewer."
          end

          prompt_text
        end
      end

      def initialize(data)
        @data = normalize_hash(data)
      end

      def to_h
        {
          "prompt" => prompt_text,
          "questions" => questions,
          "answers" => answers,
          "status" => status,
          "answered_at" => answered_at,
        }.compact
      end

      def renderable?
        questions.present? && questions.all? do |question|
          question.is_a?(Hash) &&
            question["id"].present? &&
            question["prompt"].present? &&
            Array(question["options"]).present?
        end
      end

      def prompt_text
        data["prompt"].presence
      end

      def questions
        Array(data["questions"]).filter_map do |question|
          question.is_a?(Hash) ? question.deep_stringify_keys : nil
        end
      end

      def answers
        raw_answers = data["answers"]
        return {} unless raw_answers.is_a?(Hash)

        raw_answers.deep_stringify_keys
      end

      def status
        value = data["status"].to_s
        self.class.valid_status?(value) ? value : self.class.pending_status
      end

      def answered_at
        data["answered_at"].presence
      end

      def pending?
        status == self.class.pending_status
      end

      def answered?
        status == self.class.answered_status
      end

      def question_count
        questions.size
      end

      def question_ids
        questions.pluck("id")
      end

      def answer_for(question_id)
        answers[question_id.to_s] || {}
      end

      def answered_with(responses)
        self.class.new(
          to_h.merge(
            "answers" => responses,
            "status" => self.class.answered_status,
            "answered_at" => Time.current.iso8601,
          ),
        )
      end

      def pause_message_content
        lines = ["Human-in-the-loop clarification requested. Wait for the user's answers before continuing."]
        lines << prompt_text if prompt_text.present?

        questions.each_with_index do |question, index|
          lines << "#{index + 1}. #{question["prompt"]}"
          lines << "Options: #{Array(question["options"]).join(" | ")}"
        end

        lines.join("\n")
      end

      def resume_message_content
        lines = ["Clarification answers:"]
        lines << "Clarification context: #{prompt_text}" if prompt_text.present?

        questions.each_with_index do |question, index|
          answer_text = answer_for(question["id"])["answer"].to_s
          next if answer_text.blank?

          lines << "#{index + 1}. #{question["prompt"]}"
          lines << "Answer: #{answer_text}"
        end

        lines.join("\n")
      end

      private

      attr_reader :data

      def normalize_hash(value)
        return {} unless value.is_a?(Hash)

        value.deep_stringify_keys
      end
    end
  end
end
