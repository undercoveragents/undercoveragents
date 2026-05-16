# frozen_string_literal: true

module Missions
  module Nodes
    module HttpRequestPayload
      private

      def build_request_payload(method, headers, context, node_data)
        return empty_payload unless self.class::BODY_METHODS.include?(method)

        mode = resolved_body_mode(node_data)
        return empty_payload if mode == "none"

        return build_json_payload(headers, context, node_data) if mode == "json"
        return build_raw_payload(headers, context, node_data) if mode == "raw"
        return build_form_urlencoded_payload(headers, context, node_data) if mode == "form_urlencoded"
        return build_multipart_payload(headers, context, node_data) if mode == "multipart"

        build_binary_payload(headers, context, node_data)
      end

      def build_json_payload(headers, context, node_data)
        payload = stringify_value(resolve_value(context, node_data["body"]))
        set_header_if_missing(headers, "Content-Type", "application/json") if payload.present?
        self.class::RequestPayload.new(body: payload, body_stream: nil, content_length: nil, tempfiles: [])
      end

      def build_raw_payload(headers, context, node_data)
        payload = stringify_value(resolve_value(context, node_data["body"]))
        content_type = context.interpolate(node_data["body_content_type"].to_s).strip
        set_header_if_missing(headers, "Content-Type", content_type) if content_type.present?
        self.class::RequestPayload.new(body: payload, body_stream: nil, content_length: nil, tempfiles: [])
      end

      def build_form_urlencoded_payload(headers, context, node_data)
        form_fields = resolve_pairs(context, node_data["form_urlencoded_body"])
        payload = URI.encode_www_form(form_fields)
        set_header_if_missing(headers, "Content-Type", "application/x-www-form-urlencoded") if payload.present?
        self.class::RequestPayload.new(body: payload, body_stream: nil, content_length: nil, tempfiles: [])
      end

      def build_multipart_payload(headers, context, node_data)
        parts = normalize_pairs(node_data["multipart_form_data"])
        tempfile = Tempfile.new(["mission_http_multipart", ".body"])
        tempfile.binmode
        boundary = "----MissionBoundary#{SecureRandom.hex(16)}"

        parts.each do |key, raw_value|
          append_multipart_part(tempfile, boundary, key, resolve_value(context, raw_value))
        end

        tempfile.write("--#{boundary}--\r\n")
        tempfile.rewind
        set_header_if_missing(headers, "Content-Type", "multipart/form-data; boundary=#{boundary}")
        stream_payload(tempfile, [tempfile])
      end

      def build_binary_payload(headers, context, node_data)
        source = resolve_value(context, node_data["binary_source"])
        return empty_payload unless file_variable?(source)

        tempfile = download_blob_to_tempfile(source)
        return empty_payload unless tempfile

        content_type = context.interpolate(node_data["body_content_type"].to_s).strip.presence ||
                       source["content_type"].presence || "application/octet-stream"
        set_header_if_missing(headers, "Content-Type", content_type)
        stream_payload(tempfile, [tempfile])
      end

      def stream_payload(io, tempfiles)
        self.class::RequestPayload.new(body: nil, body_stream: io, content_length: io.size, tempfiles:)
      end

      def append_multipart_part(tempfile, boundary, field_name, value)
        return if field_name.blank? || value.nil?

        if file_variable?(value)
          append_multipart_file(tempfile, boundary, field_name, value)
        else
          append_multipart_value(tempfile, boundary, field_name, value)
        end
      end

      def append_multipart_value(tempfile, boundary, field_name, value)
        tempfile.write("--#{boundary}\r\n")
        tempfile.write(%(Content-Disposition: form-data; name="#{escape_multipart(field_name)}"\r\n\r\n))
        tempfile.write(stringify_value(value))
        tempfile.write("\r\n")
      end

      def append_multipart_file(tempfile, boundary, field_name, file_meta)
        blob = ActiveStorage::Blob.find_by(id: file_meta["blob_id"])
        return unless blob

        tempfile.write("--#{boundary}\r\n")
        tempfile.write(%(Content-Disposition: form-data; name="#{escape_multipart(field_name)}"; ))
        tempfile.write(%(filename="#{escape_multipart(blob.filename.to_s)}"\r\n))
        tempfile.write("Content-Type: #{blob.content_type.presence || "application/octet-stream"}\r\n\r\n")
        blob.download { |chunk| tempfile.write(chunk) }
        tempfile.write("\r\n")
      end

      def escape_multipart(value)
        value.to_s.gsub('"', "\\\"")
      end

      def file_variable?(value)
        value.is_a?(Hash) && value["blob_id"].present? && value["filename"].present?
      end

      def download_blob_to_tempfile(meta)
        blob = ActiveStorage::Blob.find_by(id: meta["blob_id"])
        return nil unless blob

        ext = File.extname(blob.filename.to_s)
        tmpfile = Tempfile.new(["mission_http_upload", ext])
        tmpfile.binmode
        blob.download { |chunk| tmpfile.write(chunk) }
        tmpfile.rewind
        tmpfile
      end

      def resolved_body_mode(node_data)
        mode = node_data["body_mode"].to_s
        self.class::BODY_MODES.include?(mode) ? mode : "none"
      end

      def empty_payload
        self.class::RequestPayload.new(body: nil, body_stream: nil, content_length: nil, tempfiles: [])
      end
    end
  end
end
