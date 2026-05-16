# frozen_string_literal: true

module MissionDesigner
  # CRUD operations for global variables in the mission flow.
  # Global variables are available everywhere in the workflow as regular
  # variables — no node-scoping needed.
  class ManageGlobalVariablesTool < BaseTool
    DESCRIPTION = [
      "CRUD for mission global variables.",
      "Actions: list, add, update, remove.",
      "Types: string, number, boolean.",
      "Globals are seeded inputs/constants only; do not use blank or placeholder globals " \
      "for values computed later in the flow.",
      "Pass mission_id after creating a mission in the same turn.",
    ].join(" ").freeze
    MISSING_MISSION_MESSAGE = [
      "Mission context is required before managing global variables.",
      "Create or open a mission first, or pass mission_id after creating a mission in the same turn.",
    ].join(" ").freeze

    description DESCRIPTION

    param :action, desc: "Action to perform: 'list', 'add', 'update', or 'remove'"
    param :key, desc: "Variable name (required for add/update/remove)", required: false
    param :value, desc: "Variable value (for add/update)", required: false
    param :type, desc: "Variable type: 'string' (default), 'number', or 'boolean'", required: false
    param :mission_id,
          desc: "Optional mission ID or slug to edit. Use this after creating a mission in the same turn.",
          required: false

    def name
      "manage_global_variables"
    end

    def execute(action:, key: nil, value: nil, type: nil, mission_id: nil)
      mission = resolve_mission(mission_id)
      editor = Missions::FlowEditor.new(mission)
      return list_variables(editor) if action == "list"

      handle_mutation_action(action, mission, editor, { key:, value:, type: })
    rescue ArgumentError, Pundit::NotAuthorizedError => e
      e.message
    rescue StandardError => e
      "Error managing global variables: #{e.message}"
    end

    private

    def missing_mission_message
      MISSING_MISSION_MESSAGE
    end

    def resolve_mission(mission_id)
      resolve_target_mission(mission_id, missing_message: missing_mission_message)
    end

    def handle_mutation_action(action, mission, editor, attributes)
      authorize_mission_update!(mission)

      case action
      when "add" then add_variable(editor, attributes[:key], attributes[:value], attributes[:type])
      when "update" then update_variable(editor, attributes[:key], attributes[:value], attributes[:type])
      when "remove" then remove_variable(editor, attributes[:key])
      else "Unknown action: '#{action}'. Use 'list', 'add', 'update', or 'remove'."
      end
    end

    def list_variables(editor)
      vars = editor.list_global_variables
      return "No global variables defined." if vars.empty?

      lines = ["## Global Variables (#{vars.size})"]
      lines << "Globals are seeded inputs/constants only. Do not create blank or placeholder " \
               "globals for values computed later by nodes."
      vars.each do |var|
        lines << "- **#{var["key"]}** = `#{var["value"]}` (type: #{var["type"]})"
      end
      lines.join("\n")
    end

    def add_variable(editor, key, value, type)
      result = editor.add_global_variable(key:, value: value || "", type: type || "string")
      return "Error: #{result[:error]}" if result[:error]

      var = result[:variable]
      "Global variable added: **#{var["key"]}** = `#{var["value"]}` (type: #{var["type"]}). " \
        "Globals are for seeded inputs/constants, not runtime-computed values."
    end

    def update_variable(editor, key, value, type)
      result = editor.update_global_variable(key:, value:, type:)
      return "Error: #{result[:error]}" if result[:error]

      var = result[:variable]
      "Global variable updated: **#{var["key"]}** = `#{var["value"]}` (type: #{var["type"]}). " \
        "Globals are for seeded inputs/constants, not runtime-computed values."
    end

    def remove_variable(editor, key)
      result = editor.remove_global_variable(key:)
      return "Error: #{result[:error]}" if result[:error]

      "Global variable '#{result[:removed_variable]["key"]}' removed."
    end
  end
end
