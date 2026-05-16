# frozen_string_literal: true

module Missions
  module CollectionReferenceValidator
    COLLECTION_REFERENCE_PATTERN = /\A[a-z_]\w*(?:\.[a-z_]\w*)*\z/i

    module_function

    def apply(node_id:, data:, node_class:, available_names:, errors_by_node:)
      collection_input_keys(node_class).each do |field|
        reference = normalize_reference(data[field])
        next unless reference
        next if available_names[:qualified].include?(reference) || available_names[:short].include?(reference)

        errors_by_node[node_id] ||= []
        errors_by_node[node_id] << {
          field: field.to_s,
          message: "references unknown collection variable #{reference}",
        }
      end
    end

    def normalize_reference(value)
      return unless value.is_a?(String)

      normalized = value.strip
      return if normalized.blank? || !normalized.match?(COLLECTION_REFERENCE_PATTERN)

      normalized
    end

    def collection_input_keys(node_class)
      return [] unless node_class

      node_class.collection_reference_field_keys
    end
  end
end
