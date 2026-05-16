# frozen_string_literal: true

module MissionDesigner
  class ReadRunTool < BaseTool
    SELECTORS = ["latest", "recent"].freeze
    MISSING_MISSION_MESSAGE = "Create or open a mission first, or pass mission_id " \
                              "after creating a mission in the same turn."

    description "Read one mission debug run or list recent mission runs. " \
                "Use run_id for a specific run, selector='latest' for the newest run, " \
                "or selector='recent' to list runs."

    param :run_id, desc: "Optional run ID to inspect.", required: false
    param :selector,
          desc: "Run selection mode: 'latest' (default) or 'recent'.",
          required: false
    param :limit,
          desc: "Optional max number of runs when selector='recent'.",
          required: false
    param :detail,
          desc: "Response detail for a single run: 'summary' (default) or 'full'.",
          required: false
    param :mission_id,
          desc: "Optional mission ID or slug to inspect. Use this after creating a mission in the same turn.",
          required: false

    def name
      "read_mission_run"
    end

    def execute(run_id: nil, selector: nil, limit: nil, detail: nil, mission_id: nil)
      target_mission = target_mission_for(mission_id)
      authorize_mission_read!(target_mission)

      return read_specific_run(target_mission, run_id, detail:) if run_id.present?

      read_selected_runs(target_mission, selector:, limit:, detail:)
    rescue Pundit::NotAuthorizedError => e
      "Error: #{e.message}"
    rescue StandardError => e
      "Error reading mission runs: #{e.message}"
    end

    private

    def target_mission_for(mission_id)
      resolve_target_mission(mission_id, missing_message: MISSING_MISSION_MESSAGE)
    end

    def read_specific_run(target_mission, run_id, detail:)
      run = target_mission.mission_runs.find_by(id: run_id)
      return "No mission run with ID '#{run_id}' was found for '#{target_mission.name}'." unless run

      formatter_for(target_mission).format_run(run, detail:)
    end

    def read_selected_runs(target_mission, selector:, limit:, detail:)
      runs = target_mission.mission_runs.recent

      case normalize_selector(selector)
      when "latest"
        read_latest_run(target_mission, runs, detail:)
      when "recent"
        formatter_for(target_mission).format_recent_runs(runs, limit:)
      end
    end

    def read_latest_run(target_mission, runs, detail:)
      run = runs.first
      return "No mission runs found for '#{target_mission.name}'." unless run

      formatter_for(target_mission).format_run(run, detail:)
    end

    def formatter_for(target_mission)
      MissionDesigner::RunFormatter.new(mission: target_mission)
    end

    def normalize_selector(selector)
      value = selector.to_s.presence || "latest"
      raise ArgumentError, "selector must be one of: #{SELECTORS.join(", ")}" unless value.in?(SELECTORS)

      value
    end
  end
end
