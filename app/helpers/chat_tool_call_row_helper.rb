# frozen_string_literal: true

module ChatToolCallRowHelper
  def chat_tool_call_branch_label(label, child_chat)
    child_chat&.agent&.name.presence || label.to_s.sub(/\AAsk\s+/i, "")
  end

  def chat_tool_call_branch_icon_class(icon_class, child_chat)
    child_chat.present? ? "fa-solid fa-user-secret" : icon_class
  end

  def chat_tool_call_row_locals(**attributes)
    {
      status: :complete,
      phrase: nil,
      duration_label: nil,
      collapsible: false,
      section: false,
      **attributes,
    }.tap do |row|
      row[:status] = row[:status].to_s
    end
  end

  def chat_tool_call_row_classes(section: false)
    ["shared-chat__tool-call-row", ("shared-chat__tool-call-row--section" if section)].compact
  end

  def chat_tool_call_label_classes(section: false)
    ["shared-chat__tool-call-label", ("shared-chat__section-label" if section)].compact
  end

  def chat_tool_call_name_classes(section: false)
    ["shared-chat__tool-call-name", ("shared-chat__tool-call-name--section" if section)].compact
  end
end
