# frozen_string_literal: true

module TestSuites
  # Persists as a system chat.
  class EvaluationService
    PASS_THRESHOLD = 0.7

    def self.call(prompt:, expected:, actual:, test_suite:, context: {})
      new(prompt:, expected:, actual:, test_suite:, context:).call
    end

    def initialize(prompt:, expected:, actual:, test_suite:, context: {})
      @prompt = prompt
      @expected = expected
      @actual = actual
      @test_suite = test_suite
      @parent_chat = context[:parent_chat]
    end

    def call
      response = evaluator_chat.ask(build_evaluation_prompt)
      parse_evaluation(response.content)
    rescue StandardError => e
      Rails.logger.error "[TestSuites::EvaluationService] Evaluation failed: #{e.message}"
      { passed: false, score: 0.0, analysis: "Evaluation failed: #{e.message}" }
    end

    private

    def evaluator_chat
      BuiltinAgents::Runner.build_chat!(
        builtin_key: "test_evaluator",
        model_id: @test_suite.resolved_evaluation_model_id,
        temperature: @test_suite.evaluation_temperature,
        llm_context: @test_suite.resolve_evaluation_context,
        title: "Test evaluation: #{@prompt.truncate(40)}",
        execution_context: :system,
        parent_chat: @parent_chat,
        input_values: { pass_threshold: PASS_THRESHOLD },
      )
    end

    def build_evaluation_prompt
      <<~PROMPT
        ## Original Question
        #{@prompt}

        ## Expected Answer
        #{@expected}

        ## Actual Answer
        #{@actual}

        Evaluate the actual answer against the expected answer. Respond with JSON only.
      PROMPT
    end

    def parse_evaluation(content)
      # Strip any markdown code block wrapping if present
      cleaned = content.to_s.strip
                       .gsub(/\A```(?:json)?\s*/i, "")
                       .gsub(/\s*```\z/, "")
                       .strip

      data = JSON.parse(cleaned)
      score = data["score"].to_f.clamp(0.0, 1.0)

      {
        passed: score >= PASS_THRESHOLD,
        score:,
        analysis: data["analysis"].to_s.truncate(2000),
      }
    rescue JSON::ParserError => e
      Rails.logger.error "[TestSuites::EvaluationService] JSON parse error: #{e.message}"
      { passed: false, score: 0.0, analysis: "Failed to parse evaluation response: #{content.to_s.truncate(500)}" }
    end
  end
end
