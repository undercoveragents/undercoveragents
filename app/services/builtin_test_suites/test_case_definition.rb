# frozen_string_literal: true

module BuiltinTestSuites
  class TestCaseDefinition
    attr_reader :key, :name, :category, :complexity, :position, :match_type, :prompt, :expected_answer,
                :expected_child_builtin_key, :expected_tool_names, :disallow_child_chats, :required_keywords,
                :forbidden_keywords, :fixture_key

    def initialize(**attributes)
      assign_identity_attributes(attributes)
      assign_expectation_attributes(attributes)
      @fixture_key = attributes[:fixture_key].to_s.presence
    end

    def locked_attributes(suite_key:, source_path:)
      {
        source_type: "builtin",
        source_metadata: {
          "builtin_key" => key,
          "builtin_suite_key" => suite_key,
          "builtin_source" => source_path.to_s,
        },
        scenario_key: key,
      }
    end

    def editable_attributes(default_fixture_key: nil)
      {
        name:,
        prompt:,
        expected_answer:,
        match_type:,
        position:,
        category:,
        complexity:,
        fixture_key: fixture_key.presence || default_fixture_key,
        expected_child_builtin_key:,
        expected_tool_names:,
        disallow_child_chats:,
        required_keywords:,
        forbidden_keywords:,
      }
    end

    private

    def assign_identity_attributes(attributes)
      @key = attributes[:key].to_s
      @name = attributes[:name].to_s
      @category = attributes[:category].to_s
      @complexity = attributes[:complexity].to_s
      @position = attributes[:position].to_i
      @match_type = attributes[:match_type].to_s.presence || "semantic"
    end

    def assign_expectation_attributes(attributes)
      @prompt = attributes[:prompt].to_s
      @expected_answer = attributes[:expected_answer].to_s
      @expected_child_builtin_key = attributes[:expected_child_builtin_key].to_s.presence
      @expected_tool_names = Array(attributes[:expected_tool_names]).map(&:to_s)
      @disallow_child_chats = ActiveModel::Type::Boolean.new.cast(attributes[:disallow_child_chats])
      @required_keywords = Array(attributes[:required_keywords]).map(&:to_s)
      @forbidden_keywords = Array(attributes[:forbidden_keywords]).map(&:to_s)
    end
  end
end
