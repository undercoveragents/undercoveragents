# frozen_string_literal: true

module ToolsHelper
  TOOL_WIDGET_ICON_PRESETS = [
    "fa-solid fa-bolt",
    "fa-solid fa-compass",
    "fa-solid fa-gears",
    "fa-solid fa-wand-magic-sparkles",
    "fa-solid fa-brain",
    "fa-solid fa-wave-square",
  ].freeze

  def tool_type_label(tool)
    tool.type_label
  end

  def tool_type_icon(tool)
    tool.type_icon
  end

  def tool_status_label(tool)
    tool.enabled? ? "Active" : "Inactive"
  end

  def tool_status_color(tool)
    tool.enabled? ? "success" : "warning"
  end

  def tool_status_badge(tool)
    label = tool_status_label(tool)
    color = tool_status_color(tool)
    content_tag(:span, label, class: "badge badge-#{color}")
  end

  def tool_connector_display(tool)
    return "—" unless tool.toolable.respond_to?(:connector)

    connector = tool.toolable.connector
    connector&.name || "Unknown"
  end

  def tool_widget_messages_text(messages)
    Array(messages).join("\n")
  end

  def tool_widget_icon_presets(toolable)
    [toolable.class.type_icon, *TOOL_WIDGET_ICON_PRESETS].compact.uniq
  end

  def tool_widget_icon_field_options(toolable, default_presentation)
    {
      value: ToolCalls::Presentation.normalize_icon_input(toolable.tool_widget_icon),
      class: "form-input font-mono",
      placeholder: default_presentation.icon,
    }
  end

  def tool_widget_interval_field_options(toolable)
    {
      value: toolable.tool_widget_running_interval_ms,
      min: ToolCalls::Presentation::MIN_RUNNING_INTERVAL_MS,
      max: ToolCalls::Presentation::MAX_RUNNING_INTERVAL_MS,
      step: 100,
      class: "form-input",
    }
  end

  def tool_widget_messages_field_options(messages, placeholder_messages)
    {
      value: tool_widget_messages_text(messages),
      rows: 6,
      class: "form-input font-mono tool-widget-config__textarea",
      placeholder: tool_widget_messages_text(placeholder_messages),
    }
  end

  def tool_compaction_policy_label(toolable)
    policy = toolable.tool_compaction_policy.presence
    return "Default" unless policy

    tool_compaction_policy_options.find { |_, v| v == policy }&.first || "Default"
  end

  def tool_compaction_policy_options
    [
      ["Default (keep latest per identical call)", ""],
      ["Replace by time (keep only the most recent call)", "replace_by_time"],
      ["Replace by arguments (keep latest per args)", "replace_by_args"],
      ["Drop all (stub every past result)", "drop_all"],
      ["Keep all (never compact)", "keep_all"],
    ]
  end

  def tool_widget_default_presentation(tool, toolable)
    ToolCalls::PresentationDefaults.for_user_tool(
      tool_type: tool.tool_type.presence || toolable.class.type_key,
      display_name: tool_widget_label(tool, toolable),
      icon: toolable.class.type_icon,
      toolable_class: toolable.class,
    )
  end

  def tool_widget_resolved_presentation(tool, toolable)
    ToolCalls::PresentationDefaults.resolve_user_tool(
      tool_type: tool.tool_type.presence || toolable.class.type_key,
      display_name: tool_widget_label(tool, toolable),
      icon: toolable.class.type_icon,
      toolable:,
      toolable_class: toolable.class,
    )
  end

  def tool_widget_running_mode_options
    [
      ["Pick one at start", "Show one sentence chosen at random for the whole run.", "random"],
      ["Rotate while running", "Cross-fade through the set every few moments.", "rotate"],
    ]
  end

  def tool_widget_running_mode_label(mode)
    case mode.to_s
    when "rotate" then "Rotates while running"
    else "Picks one sentence at start"
    end
  end

  private

  def tool_widget_label(tool, toolable)
    tool.name.presence || toolable.class.type_label
  end
end
