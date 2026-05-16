# frozen_string_literal: true

module Missions
  module Nodes
    # Node: SubMission — executes another mission as a nested workflow.
    class SubMission
      include MissionNodePlugin

      class << self
        def node_type = "mission"
        def node_label = "Mission"
        def node_icon = "fa-solid fa-diagram-project"
        def node_color = "#8b5cf6"
        def node_category = :node
        def node_description = "Calls another mission as a sub-workflow"

        def field_contracts
          [
            field_contract(
              key: "mission_id",
              kind: :id_ref,
              value_type: :string,
              description: "ID of the sub-mission to execute",
              required: true,
            ),
            field_contract(
              key: "input_variables",
              kind: :template,
              value_type: :hash,
              description: "Map of variable names to pass into the sub-mission",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "output", type: :any, description: "Output returned by the sub-mission" },
            ],
          )
        end

        def designer_instructions
          <<~INSTRUCTIONS.strip
            ## Mission (type: "mission")
            Executes another mission as a nested sub-workflow. Max nesting depth: #{MAX_NESTING_DEPTH}.

            ### Configuration
            ```json
            {
              "mission_id": "42",
              "input_variables": {
                "query": "{{user_query}}",
                "limit": "10"
              }
            }
            ```
            - `mission_id` (required): ID of the mission to execute
            - `input_variables`: Map of variable names → expressions/values to pass as input

            Use `list_resources(kind: "missions")` to see available missions.

            ### Output Ports
            - `default`: Output

            ### Output Variables
            - `output` (any): The output returned by the sub-mission
          INSTRUCTIONS
        end
      end

      register_node!

      MAX_NESTING_DEPTH = 10
      INTERNAL_VARIABLE_PREFIXES = [
        "_trigger_data", "_nesting_depth", "_current_node_id",
        "_current_node_data", "_current_node_type", "_output_meta",
      ].freeze

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        mission_id = node_data["mission_id"]

        return NodeResult.new(status: :failure, output: "No mission_id configured") if mission_id.blank?

        mission = ::Mission.find_by(id: mission_id)
        return NodeResult.new(status: :failure, output: "Mission not found: #{mission_id}") unless mission

        depth = (context.get_variable("_nesting_depth") || 0).to_i
        if depth >= MAX_NESTING_DEPTH
          return NodeResult.new(status: :failure, output: "Maximum nesting depth (#{MAX_NESTING_DEPTH}) exceeded")
        end

        sub_run = execute_sub_mission(mission, context, node_data, depth)
        build_result(sub_run)
      rescue StandardError => e
        NodeResult.new(status: :failure, output: "Sub-mission error: #{e.message}")
      end

      private

      def execute_sub_mission(mission, context, node_data, depth)
        trigger_data = build_trigger_data(context, node_data)
        variables = { "input" => context.current_input, "_nesting_depth" => depth + 1 }
        Missions::Runner.new(mission).execute(variables:, trigger_data:)
      end

      def build_trigger_data(context, node_data)
        node_data.fetch("input_variables", {}).each_with_object({}) do |(key, expr), hash|
          hash[key] = context.interpolate(expr.to_s)
        end
      end

      def build_result(sub_run)
        if sub_run.completed?
          output_vars = extract_output_variables(sub_run)
          output = output_vars["output"] || output_vars.presence || sub_run.variables["output"]
          NodeResult.new(status: :success, output:, variables: output_vars.merge("output" => output))
        else
          NodeResult.new(status: :failure, output: sub_run.error || "Sub-mission failed")
        end
      end

      def extract_output_variables(sub_run)
        vars = sub_run.variables
        output_meta = vars["_output_meta"]
        return {} unless output_meta.is_a?(Hash)

        # Collect variables that the output node selected, excluding internal vars
        vars.except(*INTERNAL_VARIABLE_PREFIXES).reject { |k, _| k.start_with?("_") }
      end
    end
  end
end
