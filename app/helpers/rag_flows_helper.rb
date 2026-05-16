# frozen_string_literal: true

module RagFlowsHelper
  def run_status_badge(run)
    color = run_status_color(run.status)
    content_tag(:span, run.status.titleize, class: "badge badge-#{color}")
  end

  def run_status_color(status)
    {
      "completed" => "success",
      "running" => "brand",
      "failed" => "danger",
      "cancelled" => "warning",
    }[status.to_s] || "secondary"
  end

  def run_duration(run)
    seconds = run.duration
    return "—" unless seconds

    if seconds < 60
      "#{seconds.round(1)}s"
    elsif seconds < 3600
      "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
    else
      "#{(seconds / 3600).floor}h #{((seconds % 3600) / 60).floor}m"
    end
  end

  def run_stats_summary(run)
    parts = []
    parts << "#{run.documents_loaded} docs" if run.documents_loaded.positive?
    parts << "#{run.documents_skipped} skipped" if run.documents_skipped.positive?
    parts << "#{run.chunks_created} chunks" if run.chunks_created.positive?
    parts << "#{run.embeddings_generated} embeddings" if run.embeddings_generated.positive?
    parts.join(" · ").presence || "—"
  end

  def rag_flow_status_badge(pipeline)
    label = pipeline.enabled? ? "Active" : "Inactive"
    color = pipeline.enabled? ? "success" : "warning"
    content_tag(:span, label, class: "badge badge-#{color}")
  end

  def step_run_status_icon_class(step_run)
    case step_run.status
    when "running" then "fa-solid fa-spinner fa-spin"
    when "completed" then "fa-solid fa-check"
    when "failed" then "fa-solid fa-xmark"
    when "skipped" then "fa-solid fa-forward"
    else "fa-solid fa-clock"
    end
  end

  def step_run_card_status_class(step_run)
    case step_run.status
    when "running" then "rag-step-card--running"
    when "completed" then "rag-step-card--completed"
    when "failed" then "rag-step-card--failed"
    when "skipped" then "rag-step-card--skipped"
    else ""
    end
  end

  def pre_load_action_label(action)
    {
      "none" => "None (append)",
      "truncate" => "Truncate tables",
      "delete_matching" => "Delete matching documents",
    }[action.to_s] || action.to_s.titleize
  end
end
