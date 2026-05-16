# frozen_string_literal: true

module Agents
  class RuntimeContextInstructions
    def initialize(runtime_context = {})
      @runtime_context = runtime_context.to_h.deep_stringify_keys
    end

    def build
      [ui_context_block].compact.join("\n\n")
    end

    private

    attr_reader :runtime_context

    def ui_context_block
      normalized = normalized_ui_context
      return unless normalized

      [
        "<current_ui_context>",
        "This describes the admin UI state the user is currently looking at for this turn.",
        "Resolve phrases like \"this mission\", \"this agent\", \"this page\", or \"here\" against this context first.",
        page_line(normalized),
        route_line(normalized),
        path_line(normalized),
        object_line(normalized),
        operation_line(normalized),
        params_line(normalized),
        references_line(normalized),
        "</current_ui_context>",
      ].compact.join("\n")
    end

    def normalized_ui_context
      context = runtime_context["ui_context"]
      return unless context.is_a?(Hash)

      context.deep_stringify_keys
    end

    def page_line(context)
      page_name = context.dig("page", "name")
      "Page: #{page_name}" if page_name.present?
    end

    def route_line(context)
      route = route_label(context)
      "Route: #{route}" if route.present?
    end

    def path_line(context)
      path = context.dig("page", "path")
      "Path: #{path}" if path.present?
    end

    def object_line(context)
      object = context["current_object"]
      return unless object.is_a?(Hash)

      "Current object: #{object_label(object)}"
    end

    def operation_line(context)
      operation = context["operation"]
      return unless operation.is_a?(Hash)

      "Current operation: #{operation_label(operation)}"
    end

    def params_line(context)
      params = context.dig("page", "params")
      return unless params.is_a?(Hash) && params.present?

      "Visible page params: #{params_label(params)}"
    end

    def references_line(context)
      "Selected references: #{references_label(context)}"
    end

    def route_label(context)
      controller_name = context.dig("page", "controller")
      action_name = context.dig("page", "action")
      return if controller_name.blank? || action_name.blank?

      "#{controller_name}##{action_name}"
    end

    def object_label(object)
      details = []
      details << object["label"].presence
      details << "slug: #{object["slug"]}" if object["slug"].present?
      details << "id: #{object["id"]}" if object["id"].present?
      value = details.compact.join(" | ")
      value.present? ? "#{object["type"]}: #{value}" : object["type"].to_s
    end

    def operation_label(operation)
      [operation["name"], ("slug: #{operation["slug"]}" if operation["slug"].present?)].compact.join(" | ")
    end

    def params_label(params)
      params.map { |key, value| "#{key}=#{value}" }.join(", ")
    end

    def references_label(context)
      references = Array(context["references"])
      if references.empty?
        trigger = context["reference_trigger"] || "#"
        return "none (the UI reserves #{trigger} for future structured references)"
      end

      references.filter_map do |reference|
        next unless reference.is_a?(Hash)

        reference_label(reference)
      end.presence&.join(", ") || "none"
    end

    def reference_label(reference)
      details = []
      details << reference["label"].presence
      details << "id: #{reference["id"]}" if reference["id"].present?
      details << "slug: #{reference["slug"]}" if reference["slug"].present?
      details << "mention: #{reference["mention"]}" if reference["mention"].present?

      [reference["type"], details.compact.join(" | ").presence].compact.join(": ")
    end
  end
end
