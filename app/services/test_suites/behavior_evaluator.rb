# frozen_string_literal: true

module TestSuites
  class BehaviorEvaluator
    Result = Data.define(:passed, :analysis, :details) do
      def to_h
        {
          passed:,
          analysis:,
          details:,
        }
      end
    end

    def self.call(test_case:, response:, tool_names:, child_builtin_keys:, context: {})
      new(
        test_case:,
        response:,
        tool_names:,
        child_builtin_keys:,
        context:,
      ).call
    end

    def initialize(test_case:, response:, tool_names:, child_builtin_keys:, context: {})
      @test_case = test_case
      @response = response.to_s
      @tool_names = Array(tool_names).map(&:to_s)
      @child_builtin_keys = Array(child_builtin_keys).map(&:to_s)
      @context = context.to_h
    end

    def call
      detail_lines = [].tap do |lines|
        append_child_chat_checks(lines)
        append_tool_checks(lines)
        append_required_keyword_checks(lines)
        append_forbidden_keyword_checks(lines)
      end

      analysis = detail_lines.presence&.join(" ") || "Behavior checks passed."

      Result.new(
        passed: detail_lines.empty?,
        analysis:,
        details: detail_lines,
      )
    end

    private

    def append_child_chat_checks(lines)
      if @test_case.disallow_child_chats? && @child_builtin_keys.any?
        lines << "Expected no child designer chat, but saw #{@child_builtin_keys.join(", ")}."
      end

      expected_key = @test_case.expected_child_builtin_key.to_s
      return if expected_key.blank?
      return if @child_builtin_keys.include?(expected_key)

      lines << "Expected child builtin '#{expected_key}', but saw #{@child_builtin_keys.presence || ["none"]}."
    end

    def append_tool_checks(lines)
      missing_tools = @test_case.expected_tool_names.map(&:to_s) - @tool_names
      return if missing_tools.empty?

      lines << "Missing expected tool calls: #{missing_tools.join(", ")}. Saw #{@tool_names.presence || ["none"]}."
    end

    def append_required_keyword_checks(lines)
      missing_keywords = rendered_keywords(@test_case.rendered_required_keywords(@context)).reject do |keyword|
        normalized_response.include?(keyword.downcase)
      end
      return if missing_keywords.empty?

      lines << "Missing expected response keywords: #{missing_keywords.join(", ")}."
    end

    def append_forbidden_keyword_checks(lines)
      unexpected_keywords = rendered_keywords(@test_case.rendered_forbidden_keywords(@context)).select do |keyword|
        normalized_response.include?(keyword.downcase)
      end
      return if unexpected_keywords.empty?

      lines << "Response included forbidden keywords: #{unexpected_keywords.join(", ")}."
    end

    def normalized_response
      @normalized_response ||= @response.downcase
    end

    def rendered_keywords(keywords)
      Array(keywords).filter_map { |keyword| keyword.to_s.strip.presence }
    end
  end
end
