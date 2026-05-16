# frozen_string_literal: true

module Missions
  module DebugRunnerOutputSanitizer
    private

    def resolve_node_label(run, node_id)
      data = debug_flow_node_data(run, node_id)
      data["label"].presence || data["name"].presence
    end

    def resolve_node_type(run, node_id)
      debug_flow_node(run, node_id)&.dig("type")
    end

    def debug_flow_node_data(run, node_id)
      debug_flow_node(run, node_id)&.dig("data") || {}
    end

    def debug_flow_node(run, node_id)
      flow = run.flow_snapshot || {}
      (flow["nodes"] || []).find { |node| node["id"] == node_id }
    end

    def stream_name(run)
      "#{self.class::STREAM_PREFIX}_#{run.id}"
    end

    def sanitize_variables(vars)
      vars.each_with_object({}) do |(key, value), hash|
        next if key.to_s.start_with?("_")

        hash[key.to_s] = safe_output(value)
      end
    end

    def sanitize_node_outputs(outputs)
      outputs.transform_keys(&:to_s).transform_values { |value| safe_output(value) }
    end

    def safe_output(value, depth: 0)
      return self.class::BROADCAST_NESTED_NOTICE if depth >= self.class::BROADCAST_DEPTH_LIMIT

      case value
      when String
        sanitize_string_output(value)
      when Numeric, TrueClass, FalseClass, NilClass
        value
      when Array
        safe_array_output(value, depth:)
      when Hash
        safe_hash_output(value, depth:)
      else
        sanitize_string_output(value.to_s)
      end
    end

    def sanitize_string_output(value)
      str = value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      return str if str.start_with?("data:")

      truncate_debug_string(str)
    end

    def safe_array_output(value, depth:)
      items = value.first(self.class::BROADCAST_ARRAY_LIMIT).map { |item| safe_output(item, depth: depth + 1) }
      omitted_count = value.size - items.size
      items << "... (#{omitted_count} more items)" if omitted_count.positive?
      items
    end

    def safe_hash_output(value, depth:)
      return safe_file_output(value) if file_output_hash?(value)

      pairs = value.to_a.first(self.class::BROADCAST_HASH_LIMIT)
      result = pairs.each_with_object({}) do |(key, nested_value), hash|
        hash[key.to_s] = safe_output(nested_value, depth: depth + 1)
      end

      omitted_count = value.size - pairs.size
      result[self.class::BROADCAST_HASH_NOTICE_KEY] = "#{omitted_count} more keys" if omitted_count.positive?
      result
    end

    def safe_file_output(value)
      {}.tap do |file_hash|
        file_hash["filename"] = value["filename"] || value[:filename]
        file_hash["blob_id"] = value["blob_id"] || value[:blob_id]

        content_type = value["content_type"] || value[:content_type]
        byte_size = value["byte_size"] || value[:byte_size]
        file_hash["content_type"] = content_type if content_type.present?
        file_hash["byte_size"] = byte_size if byte_size.present?
      end
    end

    def file_output_hash?(value)
      (value["blob_id"] || value[:blob_id]).present? && (value["filename"] || value[:filename]).present?
    end

    def truncate_debug_string(value)
      return value if value.length <= self.class::BROADCAST_STRING_LIMIT

      "#{value[0, self.class::BROADCAST_STRING_LIMIT]}... (truncated)"
    end

    def running_node_ids_snapshot
      @running_node_ids.to_a
    end
  end
end
