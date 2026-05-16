# frozen_string_literal: true

module Missions
  module Nodes
    # Control: Delay — pauses execution for a configurable duration.
    class Delay
      include MissionNodePlugin

      class << self
        def node_type = "delay"
        def node_label = "Delay"
        def node_icon = "fa-solid fa-clock"
        def node_color = "#d97706"
        def node_category = :control
        def node_description = "Pauses execution for a specified duration"

        def field_contracts
          [
            field_contract(
              key: "duration",
              kind: :formula,
              value_type: :number,
              description: "Delay in seconds",
              required: true,
            ),
            field_contract(
              key: "unit",
              value_type: :string,
              description: "Time unit: seconds, minutes",
            ),
          ]
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "waited", type: :number, description: "Actual time waited in seconds" },
            ],
          )
        end
      end

      register_node!

      MAX_DELAY_SECONDS = 300 # 5 minutes

      def output_ports
        [{ key: "default", label: "Output" }]
      end

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        duration = resolve_duration(context, node_data)

        return NodeResult.new(status: :failure, output: "Invalid delay duration") if duration.nil? || duration.negative?

        if duration > MAX_DELAY_SECONDS
          return NodeResult.new(
            status: :failure,
            output: "Delay of #{duration}s exceeds maximum of #{MAX_DELAY_SECONDS}s",
          )
        end

        sleep(duration) if duration.positive?

        variables = { "waited" => duration }
        NodeResult.new(status: :success, output: "Waited #{duration}s", variables:)
      end

      private

      def resolve_duration(context, node_data)
        raw = node_data["duration"].to_s
        interpolated = context.interpolate(raw)
        evaluated = context.evaluate(interpolated)
        value = Float(evaluated.nil? ? interpolated : evaluated)
        unit = node_data["unit"].to_s.downcase

        case unit
        when "minutes" then value * 60
        else value # default: seconds
        end
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
