# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    class QuestionNormalizer
      INLINE_OPTIONS_PATTERN = /\b(?:options?|choices?|answers?)\s*:\s*/i
      LEADING_QUESTION_PATTERN = /\A(?:question|q)\s*\d+\s*:\s*/i

      def initialize(raw_questions, max_questions:, max_options:)
        @raw_questions = raw_questions
        @max_questions = max_questions
        @max_options = max_options
      end

      def call
        questions = Array(@raw_questions)
        raise ArgumentError, "Add at least one question." if questions.empty?

        raise ArgumentError, "Ask at most #{@max_questions} questions per request." if questions.size > @max_questions

        questions.map.with_index do |raw_question, index|
          normalize_question(raw_question, index: index + 1)
        end
      end

      private

      def normalize_question(raw_question, index:)
        question = normalized_question_hash(raw_question)

        {
          "id" => "question_#{index}",
          "prompt" => normalize_prompt(question["prompt"], index:),
          "options" => normalize_options(question, index:),
          "label" => normalize_label(question["label"], index:),
          "helper_text" => normalize_helper_text(question["helper_text"], index:),
        }.compact
      end

      def normalized_question_hash(raw_question)
        return parse_inline_question(raw_question) if raw_question.is_a?(String)

        raw_question.respond_to?(:to_h) ? raw_question.to_h.stringify_keys : {}
      end

      def parse_inline_question(raw_question)
        text = raw_question.to_s.squish
        prompt_text, options_text = text.split(INLINE_OPTIONS_PATTERN, 2)

        {
          "prompt" => prompt_text.to_s.sub(LEADING_QUESTION_PATTERN, "").squish,
          "options" => parse_inline_options(options_text),
        }
      end

      def parse_inline_options(value)
        value.to_s
             .sub(/[.?!]+\z/, "")
             .gsub(/\s+(?:or|and)\s+/i, ", ")
             .split(/\s*[,;]\s*/)
      end

      def normalize_prompt(value, index:)
        prompt = value.to_s.squish
        raise ArgumentError, "Question #{index} must include a prompt." if prompt.blank?

        return prompt if prompt.length <= ToolCallState::MAX_QUESTION_PROMPT_LENGTH

        raise ArgumentError,
              "Question #{index} must be #{ToolCallState::MAX_QUESTION_PROMPT_LENGTH} characters or fewer."
      end

      def normalize_options(question, index:)
        options = option_values(question)

        raise ArgumentError, "Question #{index} must include at least one answer option." if options.empty?

        options = truncate_options(options)
        validate_option_lengths!(options, index:)

        options
      end

      def option_values(question)
        Array(option_source(question))
          .filter_map { |option| option.to_s.squish.presence }
          .uniq
      end

      def option_source(question)
        question["options"] || question["choices"] || question["answers"]
      end

      def truncate_options(options)
        options.first(@max_options)
      end

      def validate_option_lengths!(options, index:)
        return unless options.any? { |option| option.length > ToolCallState::MAX_OPTION_LENGTH }

        raise ArgumentError,
              "Question #{index} options must be #{ToolCallState::MAX_OPTION_LENGTH} characters or fewer."
      end

      def normalize_label(value, index:)
        label = value.to_s.squish.presence || "Q#{index}"
        return label if label.length <= ToolCallState::MAX_LABEL_LENGTH

        raise ArgumentError,
              "Question #{index} label must be #{ToolCallState::MAX_LABEL_LENGTH} characters or fewer."
      end

      def normalize_helper_text(value, index:)
        helper_text = value.to_s.squish.presence
        return helper_text if helper_text.blank?
        return helper_text if helper_text.length <= ToolCallState::MAX_HELPER_TEXT_LENGTH

        raise ArgumentError,
              "Question #{index} helper text must be #{ToolCallState::MAX_HELPER_TEXT_LENGTH} characters or fewer."
      end
    end
  end
end
