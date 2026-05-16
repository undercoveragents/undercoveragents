# frozen_string_literal: true

module Missions
  module FlowEditorGlobalVariables
    VALID_VARIABLE_TYPES = ["string", "number", "boolean"].freeze

    def list_global_variables
      current_flow["global_variables"] || []
    end

    def add_global_variable(key:, value: "", type: "string")
      return error("Key is required") if key.blank?
      return validate_variable_type(type) unless VALID_VARIABLE_TYPES.include?(type)

      flow = current_flow
      flow["global_variables"] ||= []
      if flow["global_variables"].any? { |variable| variable["key"] == key }
        return error("Global variable '#{key}' already exists")
      end

      variable = { "key" => key, "value" => cast_variable_value(value, type).to_s, "type" => type }
      save_with_undo!(flow) { flow["global_variables"] << variable }

      { variable: }
    end

    def update_global_variable(key:, value: nil, type: nil)
      return error("Key is required") if key.blank?
      return validate_variable_type(type) if type.present? && VALID_VARIABLE_TYPES.exclude?(type)

      variable = find_global_variable(key)
      return variable if variable.key?(:error)

      apply_global_variable_update(variable, value:, type:)
    end

    def remove_global_variable(key:)
      return error("Key is required") if key.blank?

      flow = current_flow
      flow["global_variables"] ||= []
      removed = flow["global_variables"].find { |var| var["key"] == key }
      return error("Global variable '#{key}' not found") unless removed

      save_with_undo!(flow) { flow["global_variables"].reject! { |var| var["key"] == key } }

      { removed_variable: removed }
    end

    private

    def cast_variable_value(value, type)
      case type
      when "number" then value.to_s.include?(".") ? value.to_f : value.to_i
      when "boolean" then ActiveModel::Type::Boolean.new.cast(value)
      else value.to_s
      end
    end

    def validate_variable_type(type)
      error("Invalid type: #{type}. Must be one of: #{VALID_VARIABLE_TYPES.join(", ")}")
    end

    def find_global_variable(key)
      flow = current_flow
      flow["global_variables"] ||= []
      variable = flow["global_variables"].find { |entry| entry["key"] == key }
      variable || error("Global variable '#{key}' not found")
    end

    def apply_global_variable_update(variable, value:, type:)
      flow = current_flow
      save_with_undo!(flow) do
        variable["type"] = type if type.present?
        variable["value"] = cast_variable_value(value, variable["type"]).to_s if value.present?
      end
      { variable: }
    end
  end
end
