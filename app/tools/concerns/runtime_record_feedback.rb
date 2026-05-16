# frozen_string_literal: true

module RuntimeRecordFeedback
  private

  def success_message(result:, path:, navigated:, refreshed:)
    [
      summary_line(result),
      *record_lines(result),
      *path_lines(path),
      navigation_note(result.action, path:, navigated:, resource_key: result.definition.key),
      refresh_note(refreshed),
    ].compact.join("\n")
  end

  def summary_line(result)
    "#{result.definition.label} #{past_tense_for(result.action)} successfully."
  end

  def record_lines(result)
    return [] if result.action == :delete || result.record.blank?

    ["- ID: `#{result.record.id}`", "- Name: #{record_label(result.record)}"]
  end

  def path_lines(path)
    path.present? ? ["- Path: `#{path}`"] : []
  end

  def past_tense_for(action)
    case action
    when :create then "created"
    when :update then "updated"
    when :delete then "deleted"
    else action.to_s
    end
  end

  def navigation_note(action, path:, navigated:, resource_key: nil)
    return if path.blank?

    return navigated_note(action, resource_key:) if navigated

    return unless @runtime_context.chat&.application?

    "Navigation was not broadcast. Open the returned path manually if you still need to move the UI."
  end

  def navigated_note(action, resource_key:)
    return mission_create_navigation_note if action == :create && resource_key == "mission"

    if create_or_update?(action)
      return "Turbo navigation started. Wait for the next turn before editing the newly opened record."
    end

    "Turbo navigation started back to the resource index." if action == :delete
  end

  def mission_create_navigation_note
    "Turbo navigation started. Continue same-turn mission edits by passing the returned ID as `mission_id`."
  end

  def create_or_update?(action)
    [:create, :update].include?(action)
  end

  def refresh_note(refreshed)
    return unless refreshed

    "Current page refresh started to show the saved record."
  end

  def record_label(record)
    [record.try(:name), record.try(:title), record.try(:display_title), record.try(:slug)]
      .find(&:present?) || "#{record.class.model_name.human} ##{record.id}"
  end
end
