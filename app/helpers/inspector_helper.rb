# frozen_string_literal: true

module InspectorHelper
  def inspector_role_icon(role)
    case role
    when "system" then "fa-solid fa-gear"
    when "user" then "fa-solid fa-user"
    when "assistant" then "fa-solid fa-user-secret"
    when "tool" then "fa-solid fa-wrench"
    else "fa-solid fa-circle-question"
    end
  end

  def inspector_role_color_class(role)
    case role
    when "system" then "inspector-role-system"
    when "user" then "inspector-role-user"
    when "assistant" then "inspector-role-assistant"
    when "tool" then "inspector-role-tool"
    else "inspector-role-default"
    end
  end

  def inspector_status_badge(status)
    case status
    when "idle" then "badge-success"
    when "streaming" then "badge-brand"
    when "cancelled" then "badge-warning"
    else "badge-neutral"
    end
  end

  def inspector_execution_context_badge(execution_context)
    case execution_context.to_s
    when "playground" then "badge-brand"
    when "test" then "badge-warning"
    when "system" then "badge-neutral"
    when "user" then "badge-success"
    when "mission" then "badge-info"
    else "badge-secondary"
    end
  end

  def inspector_format_cost(cost)
    return "—" if cost.nil? || cost.zero?

    "$#{format("%.6f", cost)}"
  end

  def inspector_format_tokens(count)
    return "—" if count.nil? || count.zero?

    number_with_delimiter(count)
  end

  def inspector_format_duration(duration_ms)
    return "—" if duration_ms.nil? || duration_ms.zero?

    if duration_ms >= 60_000
      minutes = duration_ms / 60_000
      seconds = (duration_ms % 60_000) / 1000.0
      "#{minutes}m #{format("%.1f", seconds)}s"
    elsif duration_ms >= 1_000
      "#{format("%.2f", duration_ms / 1000.0)}s"
    else
      "#{duration_ms}ms"
    end
  end

  def inspector_token_summary(message)
    parts = []
    parts << "#{number_with_delimiter(message.input_tokens)}in" if message.input_tokens.to_i.positive?
    parts << "#{number_with_delimiter(message.output_tokens)}out" if message.output_tokens.to_i.positive?
    parts << "#{number_with_delimiter(message.cached_tokens)}cached" if message.cached_tokens.to_i.positive?
    parts.join(" / ")
  end

  def inspector_content_preview(content, length: 120)
    return "—" if content.blank?

    truncate(content.squish, length:)
  end

  def inspector_child_chat_cost(child)
    child.messages.sum { |m| m.calculate_cost || 0 }
  end

  def inspector_child_chat_tokens(child)
    input = child.messages.sum { |m| m.input_tokens.to_i }
    output = child.messages.sum { |m| m.output_tokens.to_i }
    { input:, output: }
  end

  def inspector_filter_active?(params)
    q = params[:q]
    return false if q.blank?

    q_hash = q.respond_to?(:to_unsafe_h) ? q.to_unsafe_h : q.to_h
    q_hash.any? { |k, v| k.to_s != "s" && v.present? }
  end
end
