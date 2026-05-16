# frozen_string_literal: true

module SkillCatalogDesigner
  module AttachmentSupport
    private

    def latest_user_message
      chat = @runtime_context&.chat
      return unless chat

      chat.messages.where(role: :user).order(:id).last
    end

    def latest_user_attachments
      message = latest_user_message
      return [] unless message

      message.attachments.attachments.includes(:blob).to_a
    end

    def attachment_names
      latest_user_attachments.map { |attachment| attachment.blob.filename.to_s }
    end

    def resolve_single_attachment(attachment_filename)
      attachments = latest_user_attachments
      return [nil, "No file attachment is available on the latest user message."] if attachments.empty?

      if attachment_filename.present?
        attachment = attachments.find { |candidate| candidate.blob.filename.to_s == attachment_filename.to_s }
        return [attachment, nil] if attachment

        return [nil, "Attachment '#{attachment_filename}' was not found on the latest user message."]
      end

      return [attachments.first, nil] if attachments.one?

      [nil, "Multiple attachments are present. Pass attachment_filename with one of: #{attachment_names.join(", ")}."]
    end

    def with_selected_upload(attachment_filename = nil)
      attachment, error = resolve_single_attachment(attachment_filename)
      return error if error

      result = nil
      attachment.blob.open do |tempfile|
        upload = ActionDispatch::Http::UploadedFile.new(
          tempfile:,
          filename: attachment.blob.filename.to_s,
          type: attachment.blob.content_type,
        )
        result = yield(upload, attachment)
      end
      result
    end
  end
end
