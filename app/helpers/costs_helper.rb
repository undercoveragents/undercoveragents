# frozen_string_literal: true

module CostsHelper
  def cost_currency(amount)
    number_to_currency(amount.to_d, precision: amount.to_d >= 1 ? 2 : 6)
  end

  def cost_percent(value)
    number_to_percentage(value, precision: 1)
  end

  def cost_status_badge_class(status)
    {
      "healthy" => "badge-success",
      "warning" => "badge-warning",
      "exceeded" => "badge-danger",
    }.fetch(status.to_s, "badge-secondary")
  end

  def cost_status_icon(status)
    {
      "healthy" => "fa-solid fa-circle-check",
      "warning" => "fa-solid fa-triangle-exclamation",
      "exceeded" => "fa-solid fa-circle-xmark",
    }.fetch(status.to_s, "fa-solid fa-circle")
  end

  def cost_status_badge(status)
    content_tag(:span, class: ["badge", cost_status_badge_class(status)]) do
      safe_join([
                  tag.i(class: cost_status_icon(status)),
                  status.to_s.humanize,
                ], " ",)
    end
  end

  def cost_period_options
    CostLimit::PERIODS.map { |period| [Costs::Period.resolve(period).label, period] }
  end

  def cost_target_type_options
    CostLimit::TARGET_TYPES.map { |type| [type.humanize, type] }
  end

  def cost_enforcement_mode_options
    CostLimit::ENFORCEMENT_MODES.map { |mode| [mode.humanize, mode] }
  end
end
