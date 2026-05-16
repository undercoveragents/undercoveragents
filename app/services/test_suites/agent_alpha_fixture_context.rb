# frozen_string_literal: true

module TestSuites
  module AgentAlphaFixtureContext
    REPORT_RECORDS = {
      operation: [:operation_id, :operation_name],
      mission: [:mission_id, :mission_name],
      agent: [:agent_id, :agent_name],
      tool: [:tool_id, :tool_name],
      client_channel: [:client_channel_id, :client_channel_name],
      api_channel: [:api_channel_id, :api_channel_name],
      skill_catalog: [:skill_catalog_id, :skill_catalog_name],
      skill: [:skill_id, :skill_name],
      test_suite: [:test_suite_id, :test_suite_name],
    }.freeze
    RENDER_CONTEXT_NAMES = {
      benchmark_operation_name: "Operation",
      benchmark_mission_name: "Mission",
      new_mission_name: "New Mission",
      renamed_mission_name: "Renamed Mission",
      benchmark_agent_name: "Agent",
      new_agent_name: "New Agent",
      renamed_agent_name: "Renamed Agent",
      benchmark_tool_name: "Tool",
      new_tool_name: "New Tool",
      renamed_tool_name: "Renamed Tool",
      benchmark_channel_name: "Client Channel",
      new_channel_name: "New Client Channel",
      renamed_channel_name: "Renamed Client Channel",
      benchmark_api_channel_name: "API Channel",
      new_api_channel_name: "New API Channel",
      benchmark_skill_catalog_name: "Skill Catalog",
      new_skill_catalog_name: "New Skill Catalog",
      benchmark_skill_name: "Refund Skill",
      new_skill_name: "New Skill",
      benchmark_test_suite_name: "Test Suite",
      new_test_suite_name: "New Test Suite",
    }.freeze

    def report_context
      REPORT_RECORDS.each_with_object({}) do |(record_method, keys), context|
        record = public_send(record_method)
        context[keys.first] = record&.id
        context[keys.last] = record&.name
      end.compact
    end

    def runtime_context_for
      base = { tenant: @tenant, user:, operation: }
      base.merge(runtime_context_records)
    end

    def runtime_context_summary
      runtime_context_for.transform_values do |value|
        if value.respond_to?(:id) && value.respond_to?(:class)
          { "class" => value.class.name, "id" => value.id, "name" => value.try(:name) }.compact
        else
          value.to_s
        end
      end
    end

    private

    def build_render_context
      base = render_context_base
      RENDER_CONTEXT_NAMES.transform_values { |suffix| "#{base} #{suffix}" }
    end

    def render_context_base
      scenario_code = scenario_key.delete("-")
      short_token = Digest::SHA1.digest(@token.to_s).bytes.first(6).map { |byte| ((byte % 26) + 97).chr }.join
      "AAB #{scenario_code} #{short_token}"
    end

    def runtime_context_records
      case test_case.category
      when "mission" then { mission: }
      when "agent" then { current_agent: agent }
      when "tool" then { current_tool: tool, mission: }
      when "channel" then { current_channel: channel_for_test_case, current_agent: agent }
      when "skills" then { current_skill_catalog: skill_catalog, current_agent: agent }
      when "test_suite" then { current_test_suite: test_suite, current_agent: agent, mission: }
      else {}
      end
    end
  end
end
