# frozen_string_literal: true

module TestSuitesHelper
  include TestSuiteMetricsHelper

  def test_suite_status_badge(test_suite)
    label = test_suite.status.capitalize
    css = test_suite.active? ? "badge-success" : "badge-secondary"
    content_tag(:span, label, class: "badge #{css}")
  end

  def test_suite_type_badge(test_suite)
    if test_suite.agent?
      content_tag(:span, class: "badge badge-brand") do
        safe_join([content_tag(:i, "", class: "fa-solid fa-user-secret mr-1"), "Agent"])
      end
    else
      content_tag(:span, class: "badge badge-warning") do
        safe_join([content_tag(:i, "", class: "fa-solid fa-diagram-project mr-1"), "Mission"])
      end
    end
  end

  def test_case_match_type_badge(test_case)
    label = test_case.match_type.capitalize
    css, icon = match_type_badge_style(test_case)
    content_tag(:span, class: "badge #{css}") do
      safe_join([content_tag(:i, "", class: "#{icon} mr-1"), label])
    end
  end

  def test_case_expected_status_badge(test_case)
    test_case_expected_status_badge_for(test_case.expected_status)
  end

  def test_case_expected_status_badge_for(status)
    css = status == "completed" ? "badge-success" : "badge-danger"
    icon = status == "completed" ? "fa-solid fa-circle-check" : "fa-solid fa-circle-xmark"
    content_tag(:span, class: "badge #{css}") do
      safe_join([content_tag(:i, "", class: "#{icon} mr-1"), status.capitalize])
    end
  end

  def test_case_behavior_summary(test_case)
    return content_tag(:span, "None", class: "text-xs text-text-muted") unless test_case.behavior_expectations?

    content_tag(:span, test_case_behavior_items(test_case).join(" • "), class: "text-xs text-text-secondary")
  end

  def test_case_list_value(value)
    Array(value).join("\n")
  end

  def test_result_check_display(value)
    return "-" if value.nil?

    value ? "passed" : "failed"
  end

  def test_run_status_badge(run)
    label = run_status_label(run)
    css = run_status_css(run)
    icon = run_status_icon(run)
    content_tag(:span, class: "badge #{css}") do
      safe_join([content_tag(:i, "", class: "#{icon} mr-1"), label])
    end
  end

  def test_case_behavior_items(test_case)
    items = []
    items << "Child: #{test_case.expected_child_builtin_key}" if test_case.expected_child_builtin_key.present?
    items << "No child chats" if test_case.disallow_child_chats?
    items << "Tools: #{test_case.expected_tool_names.join(", ")}" if test_case.expected_tool_names.any?
    items << "Keywords: #{test_case.required_keywords.join(", ")}" if test_case.required_keywords.any?
    items << "Forbidden: #{test_case.forbidden_keywords.join(", ")}" if test_case.forbidden_keywords.any?

    items
  end

  def test_result_status_badge(result)
    label = result_status_label(result)
    css = result_status_css(result)
    icon = result_status_icon(result)
    content_tag(:span, class: "badge #{css}") do
      safe_join([content_tag(:i, "", class: "#{icon} mr-1"), label])
    end
  end

  def test_run_progress_color(run)
    return "bg-neutral-300" if run.pending?
    return "bg-brand-500" if run.in_progress?
    return "bg-danger-500" if run.failed?

    rate = run.pass_rate
    if rate >= 80
      "bg-success-500"
    elsif rate >= 50
      "bg-warning-500"
    else
      "bg-danger-500"
    end
  end

  private

  def match_type_badge_style(test_case)
    case test_case.match_type
    when "exact"
      ["badge-brand", "fa-solid fa-equals"]
    when "semantic"
      ["badge-warning", "fa-solid fa-brain"]
    when "partial"
      ["badge-warning", "fa-solid fa-arrows-left-right"]
    else
      ["badge-neutral", "fa-solid fa-circle"]
    end
  end

  def run_status_label(run)
    case run.status
    when "pending" then "Pending"
    when "running" then "Running"
    when "evaluating" then "Evaluating"
    when "completed" then "Completed"
    when "failed" then "Failed"
    when "cancelled" then "Cancelled"
    else run.status.capitalize
    end
  end

  def run_status_css(run)
    case run.status
    when "pending" then "badge-secondary"
    when "running" then "badge-brand"
    when "evaluating" then "badge-warning"
    when "completed" then "badge-success"
    when "failed", "cancelled" then "badge-danger"
    else "badge-neutral"
    end
  end

  def run_status_icon(run)
    case run.status
    when "pending" then "fa-solid fa-clock"
    when "running" then "fa-solid fa-spinner fa-spin"
    when "evaluating" then "fa-solid fa-brain"
    when "completed" then "fa-solid fa-circle-check"
    when "failed" then "fa-solid fa-circle-xmark"
    when "cancelled" then "fa-solid fa-ban"
    else "fa-solid fa-circle"
    end
  end

  def result_status_label(result)
    case result.status
    when "pending" then "Pending"
    when "running" then "Running"
    when "evaluating" then "Evaluating"
    when "passed" then "Passed"
    when "failed" then "Failed"
    when "error" then "Error"
    else result.status.capitalize
    end
  end

  def result_status_css(result)
    case result.status
    when "pending" then "badge-secondary"
    when "running" then "badge-brand"
    when "evaluating" then "badge-warning"
    when "passed" then "badge-success"
    when "failed", "error" then "badge-danger"
    else "badge-neutral"
    end
  end

  def result_status_icon(result)
    case result.status
    when "pending" then "fa-solid fa-clock"
    when "running" then "fa-solid fa-spinner fa-spin"
    when "evaluating" then "fa-solid fa-brain"
    when "passed" then "fa-solid fa-circle-check"
    when "failed" then "fa-solid fa-circle-xmark"
    when "error" then "fa-solid fa-triangle-exclamation"
    else "fa-solid fa-circle"
    end
  end
end
