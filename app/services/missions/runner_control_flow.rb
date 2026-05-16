# frozen_string_literal: true

module Missions
  # Shared control-flow orchestration for mission nodes whose execution spans
  # more than a single handler call.
  module RunnerControlFlow
    private

    def execute_special_node_flow?(frame, node_details)
      case node_details[:type]
      when "iterator"
        execute_iterator_flow(frame, node_details[:id], node_details[:data])
      when "loop"
        execute_loop_flow(frame, node_details[:id], node_details[:data])
      else
        return false
      end

      true
    end

    def on_iterator_loop_done(run, graph, context, node_id)
      complete_loop_body_edges(run, graph, context, node_id)
    end

    def on_loop_done(run, graph, context, node_id)
      complete_loop_body_edges(run, graph, context, node_id)
    end
  end
end
