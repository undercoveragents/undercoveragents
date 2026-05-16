# frozen_string_literal: true

module MissionDesigner
  class RunDebugTool < BaseTool
    MISSING_MISSION_MESSAGE = "Create or open a mission first, or pass mission_id " \
                              "after creating a mission in the same turn."

    description "Run the mission in debug mode with an explicit user-requested payload and persist a MissionRun. " \
                "Use only after the user explicitly asked to run, debug, execute, or test the mission."

    param :payload,
          desc: "Optional JSON object for the mission input payload / trigger data.",
          required: false
    param :variables,
          desc: "Optional JSON object of extra debug-only variables.",
          required: false
    param :detail,
          desc: "Response detail: 'summary' (default) or 'full'.",
          required: false
    param :mission_id,
          desc: "Optional mission ID or slug to run. Use this after creating a mission in the same turn.",
          required: false

    def name
      "run_mission_debug"
    end

    def execute(payload: nil, variables: nil, detail: nil, mission_id: nil)
      target_mission = target_mission_for(mission_id)
      authorize_mission_update!(target_mission)

      trigger_data, variables_hash = prepared_inputs(target_mission, payload:, variables:)
      launch = build_launch(target_mission, trigger_data:, variables: variables_hash)
      run = execute_debug_run(target_mission, launch)

      [run_status_prefix(run), "", formatter_for(target_mission).format_run(run, detail:)].join("\n")
    rescue StandardError => e
      return "Error: #{e.message}" if e.is_a?(Pundit::NotAuthorizedError) || e.is_a?(ArgumentError)

      "Error running mission in debug mode: #{e.message}"
    end

    private

    def target_mission_for(mission_id)
      resolve_target_mission(mission_id, missing_message: MISSING_MISSION_MESSAGE)
    end

    def prepared_inputs(target_mission, payload:, variables:)
      payload_hash = parse_json_object(payload, field_name: "payload")
      variables_hash = parse_json_object(variables, field_name: "variables")
      trigger_data = target_mission.filter_trigger_data(payload_hash)
      missing_inputs = target_mission.validate_required_inputs(trigger_data)
      return [trigger_data, variables_hash] if missing_inputs.empty?

      raise ArgumentError, "Missing required mission inputs: #{missing_inputs.join(", ")}"
    end

    def execute_debug_run(target_mission, launch)
      Missions::DebugRunner.new(target_mission).resume_or_execute(
        launch.run,
        variables: launch.variables,
        trigger_data: launch.trigger_data,
      )
    end

    def run_status_prefix(run)
      case run.status.to_s
      when "completed" then "Debug run completed."
      when "failed" then "Debug run failed."
      else "Debug run finished with status #{run.status}."
      end
    end

    def build_launch(target_mission, trigger_data:, variables:)
      Missions::DebugRunLauncher.new(
        mission: target_mission,
        blob_url_resolver: ->(_blob) { raise ArgumentError, "File uploads are not supported by run_mission_debug." },
        request_data: {
          variables: variables.to_json,
          trigger_data: trigger_data.to_json,
        },
      ).call
    end

    def formatter_for(target_mission)
      MissionDesigner::RunFormatter.new(mission: target_mission)
    end

    def parse_json_object(raw, field_name:)
      return {} if raw.blank?

      parsed = case raw
               when ActionController::Parameters then raw.to_unsafe_h
               when Hash then raw
               else JSON.parse(raw)
               end
      raise ArgumentError, "#{field_name} must be a JSON object." unless parsed.is_a?(Hash)

      parsed.stringify_keys
    rescue JSON::ParserError => e
      raise ArgumentError, "Invalid JSON for #{field_name}: #{e.message}"
    end
  end
end
