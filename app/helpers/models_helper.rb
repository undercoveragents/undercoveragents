# frozen_string_literal: true

module ModelsHelper
  MODEL_QUERY_PARAM_KEYS = [
    "search",
    "provider",
    "capability",
    "input_modality",
    "output_modality",
    "sort",
    "direction",
  ].freeze
  BADGE_PALETTE = ["badge-secondary", "badge-brand", "badge-success", "badge-warning"].freeze

  def models_query_params(overrides = {})
    request.query_parameters
           .slice(*MODEL_QUERY_PARAM_KEYS)
           .merge(overrides.transform_keys(&:to_s))
           .compact_blank
  end

  def models_filters_active?
    MODEL_QUERY_PARAM_KEYS
      .difference(["sort", "direction"])
      .any? { |key| params[key].present? }
  end

  def models_next_sort_direction(column, current_sort:, current_direction:)
    current_sort == column && current_direction == "asc" ? "desc" : "asc"
  end

  def models_sort_icon(column, current_sort:, current_direction:)
    return "fa-solid fa-sort text-text-muted" unless current_sort == column

    current_direction == "asc" ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down"
  end

  def models_table_value(value)
    value.presence || "—"
  end

  def model_capabilities(model_record)
    Array(model_record.capabilities).compact_blank
  end

  def model_inline_values(values)
    compact_values = Array(values).compact_blank
    compact_values.any? ? compact_values.join(", ") : "—"
  end

  def model_modalities(model_record, key)
    return [] unless model_record.modalities.is_a?(Hash)

    Array(model_record.modalities[key]).compact_blank
  end

  def model_price_value(model_record, price_key)
    amount = model_text_pricing(model_record)[price_key.to_s]
    return "—" if amount.blank?

    "$#{format("%.2f", amount.to_f)}"
  end

  def models_badge_class(collection_key, value)
    return "badge-neutral" if collection_key.to_sym == :unknown

    normalized_value = value.to_s.downcase
    BADGE_PALETTE[normalized_value.sum % BADGE_PALETTE.length]
  end

  private

  def model_text_pricing(model_record)
    pricing = model_record.pricing
    return {} unless pricing.is_a?(Hash)

    pricing.fetch("text_tokens", pricing[:text_tokens] || {})
           .fetch("standard", pricing.dig(:text_tokens, :standard) || {})
  end
end
