# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    class ResponseProcessor
      def initialize(state, raw_responses)
        @state = state
        @raw_responses = raw_responses
        @errors = {}
        @persisted_answers = {}
      end

      def call
        return success_result(@state, @state.answers) if @state.answered?

        @state.questions.each { |question| process_question(question) }
        return failure_result if @errors.any?

        success_result(@state.answered_with(@persisted_answers), @persisted_answers)
      end

      private

      def process_question(question)
        question_id = question["id"]
        response = normalized_responses.fetch(question_id, {})
        selected_option = response["selected_option"].to_s.squish.presence
        custom_answer = response["custom_answer"].to_s.squish.presence
        answer_text = custom_answer || selected_option

        if invalid_option?(question, selected_option)
          return register_error(question_id, "Choose one of the listed options or write a custom answer.")
        end

        return register_error(question_id, custom_answer_length_error) if custom_too_long?(custom_answer)
        return register_error(question_id, "Choose an option or write a custom answer.") if answer_text.blank?

        @persisted_answers[question_id] = build_answer_payload(selected_option, custom_answer, answer_text)
      end

      def normalized_responses
        @normalized_responses ||= begin
          source = @raw_responses.respond_to?(:to_unsafe_h) ? @raw_responses.to_unsafe_h : @raw_responses.to_h
          source.each_with_object({}) do |(question_id, response), result|
            payload = response.respond_to?(:to_h) ? response.to_h.stringify_keys : {}
            result[question_id.to_s] = payload.slice("selected_option", "custom_answer")
          end
        end
      end

      def invalid_option?(question, selected_option)
        selected_option.present? && Array(question["options"]).exclude?(selected_option)
      end

      def custom_too_long?(custom_answer)
        custom_answer.present? && custom_answer.length > ToolCallState::MAX_CUSTOM_ANSWER_LENGTH
      end

      def custom_answer_length_error
        "Custom answers must be #{ToolCallState::MAX_CUSTOM_ANSWER_LENGTH} characters or fewer."
      end

      def build_answer_payload(selected_option, custom_answer, answer_text)
        {
          "selected_option" => selected_option,
          "custom_answer" => custom_answer,
          "answer" => answer_text,
        }.compact
      end

      def register_error(question_id, message)
        @errors[question_id] = message
      end

      def success_result(state, responses)
        ToolCallState::SubmissionResult.new(success?: true, state:, responses:, errors: {})
      end

      def failure_result
        merged_responses = @persisted_answers.merge(normalized_responses)
        ToolCallState::SubmissionResult.new(
          success?: false,
          state: @state,
          responses: merged_responses,
          errors: @errors,
        )
      end
    end
  end
end
