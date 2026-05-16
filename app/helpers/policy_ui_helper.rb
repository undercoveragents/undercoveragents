# frozen_string_literal: true

module PolicyUiHelper
  def policy_allows?(record, query)
    policy(record).public_send(query)
  end

  def policy_tooltip(record, query, fallback: nil)
    return fallback if policy_allows?(record, query)

    policy(record).denied_reason(query) || fallback
  end

  def policy_page_hero_action(record, query, **attributes)
    allowed = policy_allows?(record, query)

    attributes.merge(
      disabled: !allowed,
      title: allowed ? attributes[:title] : policy_tooltip(record, query, fallback: attributes[:title]),
    )
  end

  def disabled_action_classes(base_classes, disabled:)
    return base_classes unless disabled

    "#{base_classes} opacity-50 cursor-not-allowed"
  end
end
