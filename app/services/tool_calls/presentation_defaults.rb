# frozen_string_literal: true

module ToolCalls
  class PresentationDefaults
    SUBAGENT_TEMPLATE = {
      running_messages: [
        "Handing the task to %<name>s…",
        "Waiting for %<name>s to report back…",
        "Collecting %<name>s's response…",
      ],
      complete_messages: [
        "%<name>s reported back.",
        "Subagent response is ready.",
        "%<name>s's results have arrived.",
      ],
      running_mode: "rotate",
      running_interval_ms: 1600,
    }.freeze

    FALLBACK_TEMPLATE = {
      running_messages: [
        "Working on %<display_name>s…",
        "Preparing the next tool response…",
        "Collecting the latest output…",
      ],
      complete_messages: [
        "%<display_name>s is ready.",
        "Tool response collected.",
        "The result has been attached.",
      ],
    }.freeze

    class << self
      def for_builtin(definition)
        definition.presentation&.with(display_name: definition.name, icon: builtin_icon(definition)) ||
          build(display_name: definition.name, icon: builtin_icon(definition))
      end

      def resolve_user_tool(tool_type:, display_name:, icon:, toolable:, toolable_class: nil)
        defaults = for_user_tool(
          tool_type:,
          display_name:,
          icon:,
          toolable_class: toolable_class || toolable.class,
        )
        return defaults unless toolable.respond_to?(:tool_widget_override_presentation)

        defaults.merge(
          toolable.tool_widget_override_presentation(
            display_name: defaults.display_name,
            icon: defaults.icon,
          ),
        )
      rescue StandardError
        defaults || build(display_name:, icon:)
      end

      def for_user_tool(tool_type:, display_name:, icon:, toolable_class: nil)
        tool_class = resolve_tool_class(tool_type, toolable_class)
        return build(display_name:, icon:) unless tool_class.respond_to?(:tool_widget_default_presentation)

        tool_class.tool_widget_default_presentation(display_name:, icon:)
      rescue StandardError
        build(display_name:, icon:)
      end

      def for_subagent(name:)
        display_name = name
        build_from_template(
          SUBAGENT_TEMPLATE,
          display_name:,
          icon: "fa-solid fa-robot",
          replacements: { name:, display_name: },
        )
      end

      def for_fallback(display_name:, icon:)
        build_from_template(FALLBACK_TEMPLATE, display_name:, icon:)
      end

      private

      def build(display_name:, icon:, **attributes)
        Presentation.new(display_name:, icon:, **attributes)
      end

      def build_from_template(template, display_name:, icon:, replacements: {})
        resolved_attributes = interpolate_preset(
          template,
          replacements.merge(display_name:),
        )
        build(display_name:, icon:, **resolved_attributes.symbolize_keys)
      end

      def interpolate_preset(value, replacements)
        case value
        when Hash
          value.transform_values { |item| interpolate_preset(item, replacements) }
        when Array
          value.map { |item| interpolate_preset(item, replacements) }
        when String
          format(value, replacements)
        else
          value
        end
      end

      def resolve_tool_class(tool_type, toolable_class)
        return toolable_class if toolable_class.respond_to?(:tool_widget_default_presentation)

        ToolPlugin.resolve(tool_type)
      end

      def builtin_icon(definition)
        Presentation.sanitize_icon(definition.icon) || DisplayMetadataResolver::DEFAULT_ICON
      end
    end
  end
end
