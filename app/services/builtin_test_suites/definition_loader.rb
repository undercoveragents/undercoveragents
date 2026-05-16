# frozen_string_literal: true

require "toml-rb"

module BuiltinTestSuites
  class DefinitionLoader
    DEFINITION_GLOBS = [
      Rails.root.join("config/builtin_tests/**/*.toml").to_s,
      Rails.root.join("plugins/**/config/builtin_tests/**/*.toml").to_s,
    ].freeze

    class << self
      def load_all
        paths = definition_paths
        signature = definition_signature(paths)
        return @cached_definitions if @cached_signature == signature && @cached_definitions

        definitions = paths.map { |path| load_file(Pathname.new(path)) }
        detect_duplicate_keys!(definitions)
        @cached_signature = signature
        @cached_definitions = definitions.sort_by(&:key).freeze
      end

      def load_for(keys)
        requested = Array(keys).map(&:to_s)
        load_all.select { |definition| definition.key.in?(requested) }
      end

      private

      def definition_paths
        DEFINITION_GLOBS.flat_map { |glob| Dir.glob(glob) }.sort
      end

      def definition_signature(paths)
        paths.map do |path|
          stat = File.stat(path)
          [path, stat.mtime.to_f, stat.size]
        rescue Errno::ENOENT
          [path, nil, nil]
        end
      end

      def load_file(path)
        data = TomlRB.parse(path.read).deep_stringify_keys
        fixture_key = data["fixture_key"]

        Definition.new(
          key: data.fetch("key"),
          name: data.fetch("name"),
          description: data["description"],
          suite_type: data["suite_type"] || "agent",
          target_builtin_agent_key: data.fetch("target_builtin_agent_key"),
          evaluation_temperature: data["evaluation_temperature"],
          fixture_key:,
          test_cases: load_test_cases(data.fetch("test_cases"), fixture_key:),
          source_path: path,
        )
      end

      def load_test_cases(entries, fixture_key:)
        Array(entries).map.with_index do |entry, index|
          data = entry.deep_stringify_keys

          TestCaseDefinition.new(**test_case_definition_attributes(data, index:, fixture_key:))
        end
      end

      def test_case_definition_attributes(data, index:, fixture_key:)
        key = data.fetch("key")

        {
          key:,
          name: data["name"].presence || key.to_s.tr("-", " ").titleize,
          category: data["category"],
          complexity: data["complexity"],
          position: data["position"] || index,
          match_type: data["match_type"] || "semantic",
          prompt: data.fetch("prompt"),
          expected_answer: data.fetch("expected_answer"),
          expected_child_builtin_key: data["expected_child_builtin_key"],
          expected_tool_names: optional_array(data, "expected_tool_names"),
          disallow_child_chats: data["disallow_child_chats"],
          required_keywords: optional_array(data, "required_keywords"),
          forbidden_keywords: optional_array(data, "forbidden_keywords"),
          fixture_key: data["fixture_key"] || fixture_key,
        }
      end

      def optional_array(data, key)
        data[key] || []
      end

      def detect_duplicate_keys!(definitions)
        duplicate_suite_keys = definitions.group_by(&:key).select { |_key, items| items.size > 1 }.keys
        if duplicate_suite_keys.any?
          raise "Duplicate builtin test suite keys detected: #{duplicate_suite_keys.join(", ")}"
        end

        definitions.each { |definition| detect_duplicate_test_case_keys!(definition) }
      end

      def detect_duplicate_test_case_keys!(definition)
        duplicate_case_keys = definition.test_cases.group_by(&:key).select { |_key, items| items.size > 1 }.keys
        return if duplicate_case_keys.empty?

        message = [
          "Duplicate builtin test case keys detected in #{definition.key}:",
          duplicate_case_keys.join(", "),
        ].join(" ")
        raise message
      end
    end
  end
end
