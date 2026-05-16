# frozen_string_literal: true

module InspectorChatHeaderHelper
  def inspector_chat_header_meta(chat, total_cost:, token_totals:)
    meta = inspector_chat_header_base_meta(chat)

    cost_badge = inspector_chat_cost_badge(chat, total_cost)
    meta << cost_badge if cost_badge

    token_badge = inspector_chat_token_totals_badge(token_totals)
    meta << token_badge if token_badge

    model_badge = inspector_chat_model_badge(chat)
    meta << model_badge if model_badge

    meta
  end

  private

  def inspector_chat_header_base_meta(chat)
    [
      content_tag(:span, chat.status, class: "badge #{inspector_status_badge(chat.status)}"),
      content_tag(
        :span,
        chat.execution_context,
        class: "badge #{inspector_execution_context_badge(chat.execution_context)}",
      ),
    ]
  end

  def inspector_chat_cost_badge(chat, total_cost)
    return unless total_cost&.positive?

    cost_text = format("%.6f", total_cost)
    cost_text = "#{cost_text} (incl. children)" if chat.child_chats.any?

    content_tag(:span, class: "badge badge-brand") do
      safe_join([content_tag(:i, "", class: "fa-solid fa-dollar-sign mr-0.5"), cost_text])
    end
  end

  def inspector_chat_token_totals_badge(token_totals)
    return unless token_totals[:input].positive? || token_totals[:output].positive?

    token_totals_badge = safe_join(
      [
        content_tag(:i, "", class: "fa-solid fa-arrow-down mr-0.5"),
        number_with_delimiter(token_totals[:input]),
        content_tag(:span, "/", class: "mx-0.5"),
        content_tag(:i, "", class: "fa-solid fa-arrow-up mr-0.5"),
        number_with_delimiter(token_totals[:output]),
      ],
    )

    content_tag(:span, token_totals_badge, class: "badge badge-neutral")
  end

  def inspector_chat_model_badge(chat)
    return unless chat.model

    content_tag(:span, class: "badge badge-neutral") do
      safe_join([content_tag(:i, "", class: "fa-solid fa-microchip mr-0.5"), chat.model.model_id])
    end
  end
end
