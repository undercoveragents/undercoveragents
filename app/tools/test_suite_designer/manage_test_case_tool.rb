# frozen_string_literal: true

module TestSuiteDesigner
  class ManageTestCaseTool < RubyLLM::Tool
    include CurrentPageRefreshable
    include PolicyAuthorizable
    include TestCaseLookup
    include TestSuiteLookup

    ACTIONS = {
      "create" => :create,
      "update" => :update,
      "delete" => :delete,
    }.freeze
    AGENT_ATTRIBUTE_KEYS = [
      "name",
      "prompt",
      "expected_answer",
      "match_type",
      "position",
      "scenario_key",
      "category",
      "complexity",
      "fixture_key",
      "expected_child_builtin_key",
      "expected_tool_names",
      "disallow_child_chats",
      "required_keywords",
      "forbidden_keywords",
    ].freeze
    MISSION_ATTRIBUTE_KEYS = [
      "name",
      "expected_status",
      "match_type",
      "position",
      "input_variables",
      "expected_variables",
    ].freeze
    ATTRIBUTES_DESCRIPTION = [
      "Hash or JSON object string. Agent suites support name, prompt, expected_answer, match_type, position,",
      "scenario_key, category, complexity, fixture_key, expected_child_builtin_key, expected_tool_names,",
      "disallow_child_chats, required_keywords, and forbidden_keywords.",
      "Mission suites support name, expected_status, match_type, position, input_variables, and expected_variables.",
      "List fields accept arrays or newline/comma-separated strings; variable fields accept objects or JSON strings.",
    ].join(" ").freeze

    description "Create, update, or delete a test case inside the current test suite."

    param :action,
          desc: "Test case action to run: 'create', 'update', or 'delete'."

    param :test_suite_id,
          desc: "Required for create when no current test suite page is open. Accepts an ID or slug.",
          required: false

    param :test_case_id,
          desc: "Required for update and delete. Accepts a numeric ID or exact case name/prompt.",
          required: false

    param :attributes,
          desc: ATTRIBUTES_DESCRIPTION,
          required: false

    param :confirm_destroy,
          desc: "Must be true for delete actions. Only use delete when the user explicitly asked for it.",
          required: false

    def initialize(runtime_context:, current_test_suite: nil)
      super()
      @runtime_context = runtime_context
      @current_test_suite = current_test_suite
    end

    def name = "manage_test_case"

    def execute(action:, **options)
      normalized_action = ACTIONS[action.to_s]
      return "Error: Unknown action '#{action}'. Use create, update, or delete." unless normalized_action

      return create_test_case(options[:test_suite_id], options[:attributes]) if normalized_action == :create
      if normalized_action == :update
        return update_test_case(options[:test_suite_id], options[:test_case_id], options[:attributes])
      end

      delete_test_case(options[:test_suite_id], options[:test_case_id], options[:confirm_destroy])
    rescue ActiveRecord::RecordInvalid => e
      "Error: #{e.record.errors.full_messages.to_sentence}"
    rescue ActiveRecord::RecordNotFound, ArgumentError, JSON::ParserError, Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error managing test case: #{e.message}"
    end

    private

    def create_test_case(test_suite_id, raw_attributes)
      test_suite = resolve_test_suite(test_suite_id)
      return missing_test_suite_message if test_suite.nil?

      attributes = normalize_attributes(raw_attributes)
      return "Error: Provide attributes for create." if attributes.blank?

      authorize_policy!(test_suite, :update?, user: @runtime_context.user)
      test_case = test_suite.test_cases.new
      assign_test_case_attributes!(test_case, attributes)
      test_case.save!

      test_case_success_message(test_case:, action: "create", refreshed: broadcast_current_page_refresh?)
    end

    def update_test_case(test_suite_id, test_case_id, raw_attributes)
      test_suite = resolve_test_suite(test_suite_id)
      test_case = resolve_test_case(test_case_id, test_suite:)
      return missing_test_case_message if test_case.nil?

      attributes = normalize_attributes(raw_attributes)
      return "Error: Provide attributes for update." if attributes.blank?

      authorize_policy!(test_case.test_suite, :update?, user: @runtime_context.user)
      assign_test_case_attributes!(test_case, attributes)
      test_case.save!

      test_case_success_message(test_case:, action: "update", refreshed: broadcast_current_page_refresh?)
    end

    def delete_test_case(test_suite_id, test_case_id, confirm_destroy)
      test_suite = resolve_test_suite(test_suite_id)
      test_case = resolve_test_case(test_case_id, test_suite:)
      return missing_test_case_message if test_case.nil?
      return "Error: confirm_destroy must be true for delete actions." unless boolean(confirm_destroy)

      authorize_policy!(test_case.test_suite, :update?, user: @runtime_context.user)
      test_case_label = resolved_test_case_label(test_case)
      test_suite_name = test_case.test_suite.name
      test_case.destroy!

      [
        "Test case deleted successfully.",
        "- Test case: #{test_case_label}",
        "- Test suite: #{test_suite_name}",
        ("Current page refresh started to show the saved test suite." if broadcast_current_page_refresh?),
      ].compact.join("\n")
    end

    def test_case_success_message(test_case:, action:, refreshed:)
      [
        "Test case #{action}d successfully.",
        "- Test case: #{resolved_test_case_label(test_case)} (`#{test_case.id}`)",
        "- Test suite: #{test_case.test_suite.name} (`#{test_case.test_suite.id}`)",
        ("Current page refresh started to show the saved test suite." if refreshed),
      ].compact.join("\n")
    end

    def resolved_test_case_label(test_case)
      test_case.display_label.presence || "Test case ##{test_case.id}"
    end

    def assign_test_case_attributes!(test_case, attributes)
      permitted_keys = test_case.test_suite.mission? ? MISSION_ATTRIBUTE_KEYS : AGENT_ATTRIBUTE_KEYS
      normalized_attributes = attributes.slice(*permitted_keys)

      assignable_attributes = normalized_attributes.except(
        "input_variables",
        "expected_variables",
        "expected_tool_names",
        "required_keywords",
        "forbidden_keywords",
      )
      test_case.assign_attributes(assignable_attributes)
      assign_agent_behavior_attributes!(test_case, normalized_attributes) if test_case.test_suite.agent?
      return unless test_case.test_suite.mission?

      if normalized_attributes.key?("input_variables")
        test_case.input_variables = normalize_hash_attribute(normalized_attributes["input_variables"])
      end

      return unless normalized_attributes.key?("expected_variables")

      test_case.expected_variables = normalize_hash_attribute(normalized_attributes["expected_variables"])
    end

    def assign_agent_behavior_attributes!(test_case, attributes)
      ["expected_tool_names", "required_keywords", "forbidden_keywords"].each do |key|
        next unless attributes.key?(key)

        test_case.public_send(:"#{key}=", normalize_string_array_attribute(attributes[key]))
      end
    end

    def normalize_string_array_attribute(value)
      case value
      when String
        value.lines.flat_map { |line| line.split(",") }.map(&:strip).compact_blank
      when Array
        value.map { |item| item.to_s.strip }.compact_blank
      else
        raise ArgumentError, "List attributes must be an array or newline/comma-separated string."
      end
    end

    def normalize_attributes(raw_attributes)
      parsed = case raw_attributes
               when nil
                 {}
               when String
                 JSON.parse(raw_attributes)
               when Hash
                 raw_attributes
               else
                 raise ArgumentError, "Attributes must be a hash or JSON object string."
               end

      raise ArgumentError, "Attributes must be a JSON object." unless parsed.is_a?(Hash)

      parsed.deep_stringify_keys
    end

    def normalize_hash_attribute(value)
      return {} if value.blank?

      parsed = case value
               when String
                 JSON.parse(value)
               when Hash
                 value
               else
                 raise ArgumentError, "Hash attributes must be a hash or JSON object string."
               end

      raise ArgumentError, "Hash attributes must be a JSON object." unless parsed.is_a?(Hash)

      parsed.deep_stringify_keys
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end
end
