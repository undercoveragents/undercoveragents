# frozen_string_literal: true

module DashboardHelper
  def dashboard_operation_filter(selected_operation:, selected_operation_icon:, operations:)
    content_tag(:div, class: "dash-op-filter", data: { controller: "operation-switcher" }) do
      safe_join(
        [
          dashboard_operation_filter_button(selected_operation:, selected_operation_icon:),
          dashboard_operation_filter_dropdown(selected_operation:, operations:),
        ],
      )
    end
  end

  def format_token_count(count)
    if count >= 1_000_000
      "#{(count / 1_000_000.0).round(1)}M"
    elsif count >= 1_000
      "#{(count / 1_000.0).round(1)}K"
    else
      count.to_s
    end
  end

  def getting_started_progress(steps)
    done = steps.count { |s| s[:done] }
    total = steps.size
    percentage = total.positive? ? ((done.to_f / total) * 100).round : 0
    { done:, total:, percentage: }
  end

  def getting_started_step_css(step)
    step[:done] ? "dashboard-step--done" : "dashboard-step--pending"
  end

  def stat_card_trend_icon(value)
    if value.positive?
      "fa-solid fa-arrow-trend-up"
    elsif value.negative?
      "fa-solid fa-arrow-trend-down"
    else
      "fa-solid fa-minus"
    end
  end

  def time_ago_short(time)
    return "—" unless time

    distance = Time.current - time
    case distance
    when 0..59 then "just now"
    when 60..3599 then "#{(distance / 60).to_i}m ago"
    when 3600..86_399 then "#{(distance / 3600).to_i}h ago"
    when 86_400..604_799 then "#{(distance / 86_400).to_i}d ago"
    else time.strftime("%b %d")
    end
  end

  def chat_status_badge_class(chat)
    if chat.idle?
      "badge-secondary"
    elsif chat.streaming?
      "badge-brand"
    else
      "badge-warning"
    end
  end

  def mission_run_badge_class(run)
    case run.status
    when "completed" then "badge-success"
    when "running", "pending" then "badge-brand"
    when "failed" then "badge-danger"
    else "badge-secondary"
    end
  end

  def test_run_badge_class(run)
    case run.status
    when "completed" then "badge-success"
    when "running", "evaluating", "pending" then "badge-brand"
    when "failed" then "badge-danger"
    else "badge-secondary"
    end
  end

  private

  def dashboard_operation_filter_button(selected_operation:, selected_operation_icon:)
    icon_class = ToolCalls::Presentation.sanitize_icon(selected_operation_icon) || "fa-solid fa-layer-group"

    content_tag(
      :button,
      class: "dash-op-btn",
      type: "button",
      aria: { expanded: "false", haspopup: "menu" },
      data: { action: "click->operation-switcher#toggle", "operation-switcher-target": "button" },
    ) do
      safe_join(
        [
          content_tag(:i, nil, class: icon_class, data: { "operation-switcher-target": "selectedIcon" }),
          content_tag(
            :span,
            selected_operation&.name || "All Operations",
            data: { "operation-switcher-target": "selectedName" },
          ),
          content_tag(:i, nil, class: "fa-solid fa-chevron-down", data: { "operation-switcher-target": "icon" }),
        ],
      )
    end
  end

  def dashboard_operation_filter_dropdown(selected_operation:, operations:)
    content_tag(:div, class: "dash-op-dropdown", data: { "operation-switcher-target": "dropdown" }) do
      links = [dashboard_all_operations_filter_link(active: selected_operation.blank?)]

      links.concat(operations.map do |operation|
        dashboard_operation_filter_link(
          label: operation.name,
          url: admin_root_path(operation: operation.slug),
          icon: ToolCalls::Presentation.sanitize_icon(operation.icon) || "fa-solid fa-briefcase",
          operation_id: operation.id,
          active: selected_operation == operation,
        )
      end)

      safe_join(links)
    end
  end

  def dashboard_all_operations_filter_link(active:)
    dashboard_operation_filter_link(
      label: "All Operations",
      url: admin_root_path(operation: "all"),
      icon: "fa-solid fa-layer-group",
      operation_id: "",
      active:,
    )
  end

  def dashboard_operation_filter_link(label:, url:, icon:, operation_id:, active:)
    link_to url,
            class: "dash-op-item#{" active" if active}",
            data: dashboard_operation_filter_link_data(label:, icon:, operation_id:) do
      safe_join([
        content_tag(:i, nil, class: icon),
        content_tag(:span, label),
        (content_tag(:i, nil, class: "fa-solid fa-check dash-op-check") if active),
      ].compact)
    end
  end

  def dashboard_operation_filter_link_data(label:, icon:, operation_id:)
    {
      action: "click->operation-switcher#select",
      "operation-switcher-id-param": operation_id,
      "operation-switcher-name-param": label,
      "operation-switcher-icon-param": icon,
      "operation-switcher-check-class-param": "fa-solid fa-check dash-op-check",
    }
  end
end
