# frozen_string_literal: true

module Missions
  # Handles storing HTTP response bodies: text content is kept inline in JSONB,
  # binary content (images, PDFs, audio, etc.) is stored as Active Storage
  # attachments on the MissionRun to avoid database bloat.
  module BinaryResponseStorage
    extend ActiveSupport::Concern

    # Content-type prefixes treated as text (stored inline in JSONB).
    # Everything else is treated as binary and stored as an Active Storage attachment.
    TEXT_CONTENT_PREFIXES = ["text/"].freeze
    TEXT_CONTENT_TYPES = [
      "application/json", "application/xml", "application/javascript",
      "application/x-www-form-urlencoded",
    ].freeze

    private

    def build_response_body(raw_body, content_type, context, url)
      return truncate_body(raw_body) if text_content_type?(content_type)

      store_binary_response(raw_body, content_type, context, url)
    end

    def text_content_type?(content_type)
      return true if content_type.blank?

      TEXT_CONTENT_PREFIXES.any? { |prefix| content_type.start_with?(prefix) } ||
        TEXT_CONTENT_TYPES.include?(content_type) ||
        content_type.end_with?("+json", "+xml")
    end

    def store_binary_response(raw_body, content_type, context, url)
      max = self.class::MAX_BODY_SIZE
      limited = raw_body.bytesize > max ? raw_body.byteslice(0, max) : raw_body
      filename = filename_from_url(url, content_type)

      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(limited),
        filename:,
        content_type:,
      )

      context.mission_run.files.attach(blob)

      {
        "filename" => blob.filename.to_s,
        "blob_id" => blob.id,
        "content_type" => blob.content_type,
        "byte_size" => blob.byte_size,
      }
    end

    def filename_from_url(url, content_type)
      basename = File.basename(URI.parse(url).path.to_s).presence
      basename = "response_#{Time.current.to_i}" if basename.blank? || basename == "/"
      ext = Rack::Mime::MIME_TYPES.invert[content_type]
      basename += ext if ext && !basename.end_with?(ext)
      basename
    end

    def truncate_body(body)
      max = self.class::MAX_BODY_SIZE
      (u = to_utf8(body)).bytesize > max ? u.byteslice(0, max).scrub : u
    end

    # Sanitize to valid UTF-8 and strip NULL bytes, which PostgreSQL JSONB rejects.
    def to_utf8(str) = str.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\x00")
  end
end
