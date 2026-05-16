# frozen_string_literal: true

module Missions
  class NodeConfigValidator
    module FlowCheckHelpers
      private

      def parse_hash_config(value)
        case value
        when Hash
          value
        when String
          JSON.parse(value)
        else
          {}
        end
      rescue JSON::ParserError
        {}
      end

      def normalize_variable_key(key)
        normalized = key.to_s.downcase.gsub(/[^a-z0-9_]/, "_")
        normalized.presence
      end

      def append_error(errors_by_node, node_id, field, message)
        errors_by_node[node_id] ||= []
        errors_by_node[node_id] << { field:, message: }
      end

      def scan_values_for_refs(obj, refs)
        case obj
        when String
          obj.scan(/\{\{([^}]+)\}\}/).flatten.each { |ref| refs.add(ref.strip) }
        when Hash
          obj.each_value { |value| scan_values_for_refs(value, refs) }
        when Array
          obj.each { |value| scan_values_for_refs(value, refs) }
        end
      end
    end
  end
end
