# frozen_string_literal: true

module ListResourcesToolContext
  private

  def context_summary_lines
    [current_page_summary, selected_references_summary].compact
  end

  def current_page_summary
    current_object = @runtime_context&.ui_context&.dig("current_object")
    return unless current_object.is_a?(Hash)

    label = current_object["label"].presence || current_object["type"].to_s
    identifier = current_object["id"].presence || current_object["slug"].presence
    return "Current page object: #{label}" if identifier.blank?

    "Current page object: #{label} (`#{identifier}`)"
  end

  def selected_references_summary
    references = Array(@runtime_context&.ui_context&.dig("references"))
    return if references.empty?

    entries = references.filter_map { |reference| reference_summary_entry(reference) }
    return if entries.empty?

    "Selected references: #{entries.join(", ")}"
  end

  def reference_summary_entry(reference)
    return unless reference.is_a?(Hash)

    label = reference["label"].presence || reference["type"].to_s
    identifier = reference["id"].presence || reference["slug"].presence
    identifier.present? ? "#{label} (`#{identifier}`)" : label
  end
end
