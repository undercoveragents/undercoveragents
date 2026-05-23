# frozen_string_literal: true

module Llm
  class JsonResponseParser
    Result = Data.define(:data, :error) do
      def success? = error.blank?
    end

    def self.parse(content)
      return success(content) if content.is_a?(Hash) || content.is_a?(Array)

      text = content.to_s.strip
      return failure("No JSON content found") if text.blank?

      candidates_for(text).each do |candidate|
        parsed = JSON.parse(candidate)
        return success(parsed)
      rescue JSON::ParserError
        next
      end

      failure("No valid JSON object or array found")
    end

    def self.success(data)
      Result.new(data:, error: nil)
    end

    def self.failure(error)
      Result.new(data: nil, error:)
    end

    def self.candidates_for(text)
      [text, fenced_json(text), balanced_json(text)].compact_blank.uniq
    end
    private_class_method :candidates_for

    def self.fenced_json(text)
      match = text.match(/```(?:json)?\s*(.*?)```/m)
      match&.[](1)&.strip
    end
    private_class_method :fenced_json

    def self.balanced_json(text)
      start_index = first_json_start(text)
      return if start_index.nil?

      extract_balanced(text, start_index)
    end
    private_class_method :balanced_json

    def self.first_json_start(text)
      object_index = text.index("{")
      array_index = text.index("[")
      [object_index, array_index].compact.min
    end
    private_class_method :first_json_start

    # rubocop:disable Metrics/CyclomaticComplexity
    def self.extract_balanced(text, start_index)
      stack = []
      in_string = false
      escaped = false

      text.each_char.with_index do |char, index|
        next if index < start_index

        in_string, escaped = update_string_state(char, in_string, escaped)
        next if in_string || escaped

        stack << char if ["{", "["].include?(char)
        stack.pop if matching_close?(stack.last, char)
        return text[start_index..index] if stack.empty?
      end

      nil
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    private_class_method :extract_balanced

    def self.update_string_state(char, in_string, escaped)
      return [in_string, false] if escaped
      return [in_string, true] if in_string && char == "\\"
      return [!in_string, false] if char == '"'

      [in_string, false]
    end
    private_class_method :update_string_state

    def self.matching_close?(opening, char)
      (opening == "{" && char == "}") || (opening == "[" && char == "]")
    end
    private_class_method :matching_close?
  end
end
