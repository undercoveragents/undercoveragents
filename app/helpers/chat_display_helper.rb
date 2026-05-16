# frozen_string_literal: true

module ChatDisplayHelper
  def chat_attachment_icon(attachment)
    content_type = attachment.content_type.to_s
    case content_type
    when %r{^image/} then "fa-file-image"
    when "application/pdf" then "fa-file-pdf"
    when %r{^audio/} then "fa-file-audio"
    when %r{^video/} then "fa-file-video"
    when %r{^text/} then "fa-file-lines"
    else "fa-file"
    end
  end

  def chat_display_title(chat)
    chat.display_title_for_ui
  end

  def chat_message_time(message)
    message.created_at.strftime("%I:%M %p")
  end

  def chat_active?(chat, current_chat)
    current_chat&.id == chat.id
  end

  def chat_status_icon(status)
    case status.to_s
    when "streaming"
      "fa-solid fa-spinner fa-spin"
    when "cancelled"
      "fa-solid fa-ban"
    else
      "fa-solid fa-circle"
    end
  end

  def chat_role_label(role)
    case role.to_s
    when "user"
      "You"
    when "assistant"
      "Assistant"
    else
      role.to_s.humanize
    end
  end

  def chat_message_display_content(message)
    message.display_content
  end

  def chat_message_display_html(message)
    content = chat_message_display_content(message).to_s
    references = chat_message_inline_references(message)
    return ERB::Util.html_escape(content) if references.empty?

    pattern = Regexp.union(references.pluck("mention"))
    parts = content.split(/(#{pattern})/)
    safe_join(parts.map { |part| chat_message_content_part(part, references) })
  end

  def chat_message_references(message)
    message.chat_references
  end

  def chat_message_context_references(message)
    content = chat_message_display_content(message).to_s
    chat_message_references(message).reject do |reference|
      reference["mention"].present? && content.include?(reference["mention"])
    end
  end

  def chat_reference_badge_text(reference)
    reference["label"].presence ||
      reference["display_mention"].presence ||
      reference["mention"].presence ||
      reference["display_tag"].presence ||
      "Reference"
  end

  def chat_reference_badge_title(reference)
    [
      reference["type"].presence,
      reference["label"].presence,
      ("id: #{reference["id"]}" if reference["id"].present?),
      ("slug: #{reference["slug"]}" if reference["slug"].present?),
    ].compact.join(" · ")
  end

  private

  def chat_message_inline_references(message)
    content = chat_message_display_content(message).to_s
    inline_references = chat_message_references(message).select do |reference|
      reference["mention"].present? && content.include?(reference["mention"])
    end
    inline_references.sort_by { |reference| -reference["mention"].length }
  end

  def chat_message_content_part(part, references)
    reference = references.find { |candidate| candidate["mention"] == part }
    return ERB::Util.html_escape(part) unless reference

    tag.code(
      chat_reference_badge_text(reference),
      class: "shared-chat__inline-reference",
      title: chat_reference_badge_title(reference),
    )
  end
end
