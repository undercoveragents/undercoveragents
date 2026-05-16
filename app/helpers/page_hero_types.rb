# frozen_string_literal: true

module PageHeroTypes
  PROMOTABLE_ACTION_STYLES = [:primary, :secondary].freeze

  BackLink = Data.define(:label, :url)
  Eyebrow = Data.define(:label, :icon)
  ControlGroup = Data.define(:kind, :entries)
  Action = Data.define(
    :label,
    :url,
    :icon,
    :style,
    :http_method,
    :params,
    :data,
    :title,
    :disabled,
    :form_id,
  ) do
    def button_classes
      classes = case style.to_sym
                when :primary then "btn btn-primary"
                when :toolbar, :secondary then "btn btn-secondary"
                when :danger_outline then "btn btn-danger-outline"
                else style.to_s.presence || "btn btn-secondary"
                end

      return classes unless disabled

      "#{classes} opacity-50 cursor-not-allowed pointer-events-none"
    end

    def form_submit? = form_id.present?
    def non_get? = !form_submit? && http_method.present? && http_method.to_sym != :get
    def delete_action? = !form_submit? && http_method.present? && http_method.to_sym == :delete
    def primary_action? = style.to_sym == :primary
    def promotable_primary? = !delete_action? && style.to_sym.in?(PROMOTABLE_ACTION_STYLES)
  end

  Component = Data.define(
    :variant,
    :theme,
    :eyebrow,
    :back_link,
    :title_icon,
    :title_lines,
    :record_title,
    :description,
    :meta,
    :actions,
    :sticky,
  ) do
    def root_classes
      [
        "page-hero",
        "page-hero--#{variant}",
        ("page-hero--#{theme}" if theme.present?),
        ("page-hero--sticky" if sticky?),
        (panel? ? "page-hero--has-panel" : "page-hero--no-panel"),
      ].compact.join(" ")
    end

    def dashboard? = variant == :dashboard
    def panel? = control_groups.any?
    def actions? = actions.any?
    def meta? = meta.any?
    def sticky? = sticky || actions.any?(&:form_submit?)

    def header_title
      return eyebrow.label if dashboard? && eyebrow&.label.present?

      title_lines.first
    end

    def header_icon
      return eyebrow.icon if dashboard? && eyebrow&.icon.present?

      title_icon.presence || eyebrow&.icon.presence
    end

    def record_title? = record_title.present?

    def action_groups
      [navigation_group, delete_action_group, secondary_action_group, primary_action_group].compact
    end

    def control_groups
      groups = []
      groups << ControlGroup.new(kind: :meta, entries: meta) if meta?
      action_groups.each do |group|
        groups << ControlGroup.new(kind: :actions, entries: group)
      end
      groups
    end

    private

    def navigation_group = back_action ? [back_action] : nil

    def delete_action_group = actions.select(&:delete_action?).presence

    def secondary_action_group
      actions.reject(&:delete_action?).reject(&:primary_action?).presence
    end

    def primary_action_group = actions.select(&:primary_action?).presence

    def back_action
      return unless back_link

      Action.new(
        label: back_link.label,
        url: back_link.url,
        icon: "fa-solid fa-arrow-left",
        style: :toolbar,
        http_method: nil,
        params: {},
        data: {},
        title: nil,
        disabled: false,
        form_id: nil,
      )
    end
  end
end
