# frozen_string_literal: true

module Missions
  module DebugRunnerBroadcasts
    private

    def broadcast_node_state(run, node_id, node_type, state, attributes = {})
      attrs = node_state_attributes(node_id, node_type, state, attributes)
      attr_str = attrs.map { |key, value| "#{key}=\"#{ERB::Util.html_escape(value)}\"" }.join(" ")

      Turbo::StreamsChannel.broadcast_append_to(
        stream_name(run),
        target: "mission-node-events",
        html: "<div #{attr_str}></div>",
      )
    end

    def node_state_attributes(node_id, node_type, state, attributes)
      attrs = {
        "data-node-id" => node_id,
        "data-node-type" => node_type,
        "data-state" => state,
      }
      attrs["data-error"] = attributes[:error] if attributes[:error]
      attrs["data-next-port"] = attributes[:next_port] if attributes[:next_port]
      attrs["data-duration-ms"] = attributes[:duration_ms] if attributes[:duration_ms]
      attrs["data-completed-count"] = attributes[:completed_count] if attributes[:completed_count]&.positive?
      attrs
    end

    def broadcast_node_completed(run, request_arg, result_arg, result_or_label = nil, context = nil)
      request, result, node_label = completed_node_broadcast_args(
        request_arg,
        result_arg,
        result_or_label,
        context,
      )
      return unless result

      log_entry = request.context.execution_log.rfind { |execution| execution.node_id == request.node_id }
      duration_ms = completed_log_duration_ms(log_entry)

      broadcast_completed_node_state(run, request, result, duration_ms)
      broadcast_completed_timeline_entry(run, request, result, log_entry:, node_label:, duration_ms:)
    end

    def broadcast_completed_node_state(run, request, result, duration_ms)
      broadcast_node_state(run, request.node_id, request.node_type, result.status.to_s,
                           next_port: result.next_port, duration_ms:,
                           completed_count: @node_completion_counts[request.node_id],)
    end

    def broadcast_completed_timeline_entry(run, request, result, details)
      entry_args = details.values_at(:log_entry, :node_label, :duration_ms)

      Turbo::StreamsChannel.broadcast_append_to(
        stream_name(run),
        target: "mission-timeline-entries",
        partial: "admin/missions/debug/timeline_entry",
        locals: { entry: completed_timeline_entry(request, result, *entry_args) },
      )
    end

    def completed_timeline_entry(request, result, log_entry, node_label, duration_ms)
      {
        node_id: request.node_id,
        node_type: request.node_type,
        node_label:,
        status: result.status.to_s,
        input: safe_output(log_entry&.input),
        output: safe_output(result.output),
        next_port: result.next_port,
        variables_set: result.variables.transform_keys(&:to_s),
        duration_ms:,
        error: nil,
      }
    end

    def broadcast_variables(run, context)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(run),
        target: "mission-variables-content",
        partial: "admin/missions/debug/variables",
        locals: {
          variables: sanitize_variables(context.variables),
          node_outputs: sanitize_node_outputs(context.node_outputs),
        },
      )
    end

    def broadcast_remaining_cancelled(run, output_node_id)
      running_node_ids_snapshot.each do |node_id|
        next if node_id == output_node_id

        safely_broadcast { broadcast_node_state(run, node_id, nil, "cancelled") }
        safely_broadcast { broadcast_cancelled_timeline_entry(run, node_id) }
      end
    end

    def edge_state_changed(run, _context, edge_id, state)
      safely_broadcast { broadcast_edge_state(run, edge_id, state) }
    end

    def node_state_changed(run, _context, node_id, state, node_type: nil)
      safely_broadcast { broadcast_node_state(run, node_id, node_type, state) }
    end

    def broadcast_edge_state(run, edge_id, state)
      Turbo::StreamsChannel.broadcast_append_to(
        stream_name(run),
        target: "mission-node-events",
        html: edge_state_html(edge_id, state),
      )
    end

    def edge_state_html(edge_id, state)
      escaped_edge_id = ERB::Util.html_escape(edge_id)
      escaped_state = ERB::Util.html_escape(state)
      "<div data-edge-id=\"#{escaped_edge_id}\" data-edge-state=\"#{escaped_state}\"></div>"
    end

    def broadcast_iterator_or_loop_done(run, context, node_id, node_type, started_at)
      duration_ms = ((Time.current - started_at) * 1000).round(1)
      iteration_count = iteration_count_from_context(context, node_type, node_id)
      safely_broadcast do
        broadcast_node_state(
          run, node_id, node_type, "success",
          next_port: "done",
          duration_ms:,
          completed_count: iteration_count,
        )
      end
      safely_broadcast { broadcast_control_timeline_entry(run, context, node_id, node_type, duration_ms) }
      safely_broadcast { broadcast_variables(run, context) }
    end

    def broadcast_all_edges_reset(run)
      flow = run.flow_snapshot || {}
      (flow["edges"] || []).each do |edge|
        next if edge["id"].blank?

        safely_broadcast { broadcast_edge_state(run, edge["id"], "reset") }
      end
    end

    def iteration_count_from_context(context, node_type, node_id)
      if node_type == "iterator"
        Array(context.node_outputs[node_id]).size
      else
        context.execution_log.count do |execution|
          execution.node_id == node_id && execution.node_type == "loop" && execution.next_port == "loop"
        end
      end
    end

    def execute_control_node_flow_with_broadcasts(run, node_id, node_type, started_ats)
      @running_node_ids.add(node_id)
      safely_broadcast { broadcast_node_state(run, node_id, node_type, "running") }
      started_ats[node_id] = Time.current

      yield
    rescue Missions::OutputReached
      @running_node_ids.delete(node_id)
      raise
    rescue StandardError => e
      @running_node_ids.delete(node_id)
      safely_broadcast { broadcast_node_state(run, node_id, node_type, "failure", error: e.message) }
      raise
    end

    def broadcast_control_node_done(run, context, node_id, node_type, started_ats)
      @running_node_ids.delete(node_id)
      started_at = started_ats.delete(node_id) || Time.current
      broadcast_iterator_or_loop_done(run, context, node_id, node_type, started_at)
    end

    def broadcast_control_timeline_entry(run, context, node_id, node_type, duration_ms)
      log_entry = context.execution_log.rfind { |execution| execution.node_id == node_id }
      logged_output = log_entry ? log_entry.output : context.node_outputs[node_id]

      Turbo::StreamsChannel.broadcast_append_to(
        stream_name(run),
        target: "mission-timeline-entries",
        partial: "admin/missions/debug/timeline_entry",
        locals: { entry: control_timeline_entry(run, node_id, node_type, log_entry, logged_output:, duration_ms:) },
      )
    end

    def control_timeline_entry(run, node_id, node_type, log_entry, attributes = {})
      {
        node_id:,
        node_type:,
        node_label: resolve_node_label(run, node_id),
        status: "success",
        input: safe_output(log_entry&.input),
        output: safe_output(attributes[:logged_output]),
        next_port: "done",
        variables_set: {},
        duration_ms: attributes[:duration_ms],
        error: nil,
      }
    end

    def broadcast_cancelled_timeline_entry(run, node_id)
      Turbo::StreamsChannel.broadcast_append_to(
        stream_name(run),
        target: "mission-timeline-entries",
        partial: "admin/missions/debug/timeline_entry",
        locals: { entry: cancelled_timeline_entry(run, node_id) },
      )
    end

    def cancelled_timeline_entry(run, node_id)
      {
        node_id:,
        node_type: resolve_node_type(run, node_id),
        node_label: resolve_node_label(run, node_id),
        status: "cancelled",
        input: nil,
        output: nil,
        next_port: nil,
        variables_set: {},
        duration_ms: nil,
        error: nil,
      }
    end

    def safely_broadcast
      yield
    rescue PG::InvalidParameterValue => e
      Rails.logger.warn("[DebugRunner] Broadcast skipped — PG payload too large: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[DebugRunner] Broadcast error: #{e.class} — #{e.message} (#{e.backtrace&.first})")
    end
  end
end
