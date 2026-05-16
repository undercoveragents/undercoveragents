# frozen_string_literal: true

module MissionControlHelper
  NODE_TYPE_ICONS = {
    "agent" => "fa-solid fa-user-secret",
    "llm" => "fa-solid fa-brain",
    "condition" => "fa-solid fa-code-branch",
    "switch" => "fa-solid fa-arrows-split-up-and-left",
    "iterator" => "fa-solid fa-rotate",
    "loop" => "fa-solid fa-arrows-rotate",
    "set_variable" => "fa-solid fa-equals",
    "input" => "fa-solid fa-right-to-bracket",
    "output" => "fa-solid fa-right-from-bracket",
    "mission" => "fa-solid fa-diagram-project",
    "code" => "fa-solid fa-code",
    "http_request" => "fa-solid fa-globe",
    "generate_image" => "fa-solid fa-image",
    "write_file" => "fa-solid fa-file-export",
  }.freeze

  NODE_TYPE_COLORS = {
    "agent" => "mc-node-agent",
    "llm" => "mc-node-llm",
    "condition" => "mc-node-control",
    "switch" => "mc-node-control",
    "iterator" => "mc-node-loop",
    "loop" => "mc-node-loop",
    "input" => "mc-node-io",
    "output" => "mc-node-io",
    "mission" => "mc-node-mission",
    "code" => "mc-node-code",
    "http_request" => "mc-node-http",
    "generate_image" => "mc-node-image",
  }.freeze

  STATUS_BADGES = {
    "completed" => "badge-success",
    "running" => "badge-brand",
    "pending" => "badge-secondary",
    "paused" => "badge-warning",
    "cancelled" => "badge-warning",
    "failed" => "badge-danger",
  }.freeze

  def mc_status_badge(status)
    STATUS_BADGES.fetch(status.to_s, "badge-secondary")
  end

  def mc_status_icon(status)
    case status.to_s
    when "completed" then "fa-solid fa-circle-check"
    when "running" then "fa-solid fa-spinner fa-spin"
    when "pending" then "fa-solid fa-clock"
    when "paused" then "fa-solid fa-pause"
    when "failed" then "fa-solid fa-circle-xmark"
    when "cancelled" then "fa-solid fa-ban"
    else "fa-solid fa-circle-question"
    end
  end

  def mc_node_type_icon(node_type)
    NODE_TYPE_ICONS.fetch(node_type.to_s, "fa-solid fa-cube")
  end

  def mc_node_type_color(node_type)
    NODE_TYPE_COLORS.fetch(node_type.to_s, "mc-node-default")
  end

  def mc_execution_status_color(status)
    case status.to_sym
    when :success then "mc-exec-success"
    when :failure then "mc-exec-failure"
    when :skip then "mc-exec-skip"
    else "mc-exec-default"
    end
  end

  def mc_format_duration(duration_ms)
    return "—" if duration_ms.nil?

    total_ms = duration_ms.to_f
    return "—" if total_ms <= 0

    total_seconds = total_ms / 1000.0
    if total_seconds >= 3600
      hours = (total_seconds / 3600).floor
      minutes = ((total_seconds % 3600) / 60).floor
      seconds = total_seconds % 60
      "#{hours}h #{minutes}m #{format("%.1f", seconds)}s"
    elsif total_seconds >= 60
      minutes = (total_seconds / 60).floor
      seconds = total_seconds % 60
      "#{minutes}m #{format("%.1f", seconds)}s"
    elsif total_seconds >= 1
      "#{format("%.2f", total_seconds)}s"
    else
      "#{total_ms.round}ms"
    end
  end

  def mc_format_run_duration(run)
    return "—" unless run.duration

    mc_format_duration(run.duration * 1000)
  end

  def mc_node_label(flow_nodes, node_id)
    node = flow_nodes[node_id]
    return node_id unless node

    data = node["data"] || {}
    data["label"].presence || data["name"].presence || node_id
  end

  def mc_filter_active?(params)
    q = params[:q]
    return false if q.blank?

    q_hash = q.respond_to?(:to_unsafe_h) ? q.to_unsafe_h : q.to_h
    q_hash.any? { |k, v| k.to_s != "s" && v.present? }
  end

  def mc_node_output_preview(output, length: 200)
    return "—" if output.blank?

    text = output.is_a?(Hash) ? output.to_json : output.to_s
    truncate(text.squish, length:)
  end

  def mc_chat_cost(_chat)
    0
  end

  def mc_chat_tokens(chat)
    input = chat.messages.sum(Message.total_input_activity_sum)
    output = chat.messages.sum(:output_tokens)
    { input:, output: }
  end
end
