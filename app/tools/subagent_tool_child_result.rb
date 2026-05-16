# frozen_string_literal: true

module SubagentToolChildResult
  private

  def decorate_nested_subagent_response(chat, content)
    return content unless structured_child_result_enabled?

    payload = structured_child_result_payload(chat)
    return content unless actionable_child_result_payload?(payload)

    [content.presence, structured_child_result_block(payload)].compact.join("\n\n")
  end

  def structured_child_result_enabled?
    builtin_key = @agent.builtin_key.to_s
    agent_type = @agent.agent_type.to_s

    builtin_key.end_with?("_designer") || agent_type.end_with?("_designer")
  end

  def actionable_child_result_payload?(payload)
    payload["record_ids"].any? || payload["warnings"].any? || payload["blockers"].any?
  end

  def structured_child_result_block(payload)
    payload = JSON.generate(payload)

    ["<#{SubagentTool::CHILD_RESULT_TAG}>", payload, "</#{SubagentTool::CHILD_RESULT_TAG}>"].join("\n")
  end

  def structured_child_result_payload(chat)
    messages = child_messages(chat)
    warnings = child_result_warnings(messages)
    blockers = child_result_blockers(messages)

    {
      "status" => child_result_status(warnings:, blockers:),
      "record_ids" => child_result_record_ids(messages),
      "warnings" => warnings,
      "blockers" => blockers,
    }
  end

  def child_result_status(warnings:, blockers:)
    return "blocked" if blockers.any?
    return "warning" if warnings.any?

    "success"
  end

  def child_messages(chat)
    return [] unless chat.respond_to?(:messages)

    messages = chat.messages

    if messages.respond_to?(:where)
      return messages.where(role: SubagentTool::TOOL_MESSAGE_ROLES).order(:created_at, :id).to_a
    end

    Array(messages).select do |message|
      SubagentTool::TOOL_MESSAGE_ROLES.include?(message.respond_to?(:role) ? message.role.to_s : nil)
    end
  end

  def child_result_record_ids(messages)
    records = messages.filter_map do |message|
      parse_runtime_record_result(message.content.to_s)
    end

    records.uniq { |entry| [entry["resource"], entry["id"], entry["action"]] }
  end

  def parse_runtime_record_result(content)
    lines = normalized_content_lines(content)
    summary_match = runtime_record_summary_match(lines)
    return unless summary_match

    definition = RuntimeRecords::Registry.definition_for_label(summary_match[:label])
    return unless definition

    identifier = runtime_record_identifier(lines)
    return if identifier.blank?

    label = lines.find { |line| line.start_with?("- Name: ") }&.delete_prefix("- Name: ")

    {
      "resource" => definition.key,
      "id" => identifier,
      "label" => label,
      "action" => summary_match[:action],
    }.compact
  end

  def runtime_record_summary_match(lines)
    summary_line = lines.find { |line| line.match?(/\A.+? (created|updated|deleted) successfully\.\z/) }
    summary_line&.match(/\A(?<label>.+?) (?<action>created|updated|deleted) successfully\.\z/)
  end

  def runtime_record_identifier(lines)
    lines.find { |line| line.start_with?("- ID:") }
         &.match(/\A- ID: `(?<id>[^`]+)`\z/)
         &.[](:id)
  end

  def child_result_warnings(messages)
    messages.flat_map do |message|
      section_items(message.content.to_s, "Warnings")
    end.uniq
  end

  def child_result_blockers(messages)
    messages.flat_map do |message|
      normalized_content_lines(message.content.to_s).select do |line|
        line.start_with?("Error:", "Failed to manage", "Failed to navigate") ||
          line.include?(ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
      end
    end.uniq
  end

  def section_items(content, heading)
    lines = normalized_content_lines(content)
    heading_index = lines.index("## #{heading}")
    return [] unless heading_index

    lines[(heading_index + 1)..]
      .to_a
      .take_while { |line| !line.start_with?("## ") }
      .filter_map { |line| line.delete_prefix("- ") if line.start_with?("- ") }
  end

  def normalized_content_lines(content)
    content.to_s.lines.map(&:strip).reject(&:empty?)
  end
end
