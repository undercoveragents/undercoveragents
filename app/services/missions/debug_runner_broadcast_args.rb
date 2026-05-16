# frozen_string_literal: true

module Missions
  module DebugRunnerBroadcastArgs
    NodeBroadcastRequest = Data.define(:context, :node_id, :node_type)

    private

    def completed_node_broadcast_args(request_or_node_id, result_or_node_type, result_or_label, context)
      return [request_or_node_id, result_or_node_type, result_or_label] if request_or_node_id.respond_to?(:node_id)

      request = NodeBroadcastRequest.new(context:, node_id: request_or_node_id, node_type: result_or_node_type)
      [request, result_or_label, nil]
    end

    def completed_log_duration_ms(log_entry)
      ((log_entry.finished_at - log_entry.started_at) * 1000).round(1) if log_entry
    end
  end
end
