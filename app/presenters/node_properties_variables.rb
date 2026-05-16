# frozen_string_literal: true

module NodePropertiesVariables
  FILE_OUTPUT_TYPES = ["generate_image", "write_file"].freeze
  FILE_FIELD_TYPES = ["file", "file_array"].freeze

  def upstream_variables
    @upstream_variables ||= build_upstream_variables
  end

  def output_variables
    @output_variables ||= build_output_variables
  end

  def selectable_upstream_variables
    upstream_variables.reject { |variable| variable[:name].start_with?("_") }
  end

  def upstream_file_variables
    @upstream_file_variables ||= build_upstream_file_variables
  end

  private

  def build_upstream_variables
    upstream_variable_entries.map do |entry|
      { name: entry.qualified_name || entry.name,
        description: entry.description,
        type: "upstream",
        source: entry.node_name, }
    end
  end

  def build_output_variables
    node_name = derive_node_name
    raw = variable_schema.outputs.reject { |variable| variable.name == "*" }
    dynamic = expand_dynamic_outputs if variable_schema.outputs.any? { |variable| variable.name == "*" }
    raw = raw.map { |variable| output_variable_attributes(variable) } + (dynamic || [])
    raw.map { |variable| format_output_variable(node_name, variable) }
  end

  def output_variable_attributes(variable)
    { name: variable.name, description: variable.description, port: variable.port }
  end

  def format_output_variable(node_name, variable)
    {
      name: "#{node_name}.#{variable[:name]}",
      description: variable[:description],
      type: "out",
      port: variable[:port],
    }
  end

  def expand_dynamic_outputs
    results = []
    expand_assignment_outputs(results)
    expand_field_outputs(results)
    expand_extraction_outputs(results)
    expand_code_output_variables(results)
    results
  end

  def expand_assignment_outputs(results)
    assignments.each_key do |key|
      results << { name: key, description: "User-defined variable", port: nil }
    end
  end

  def expand_field_outputs(results)
    fields.each do |field|
      next if field["variable_name"].blank?

      results << { name: field["variable_name"], description: field["label"] || "Input field", port: nil }
    end
  end

  def expand_extraction_outputs(results)
    extractions.each_key do |key|
      results << { name: key, description: "Extracted from #{extractions[key]}", port: nil }
    end
  end

  def expand_code_output_variables(results)
    code_output_variables.each do |output_variable|
      next if output_variable["name"].blank?

      results << {
        name: output_variable["name"],
        description: output_variable["description"].presence || "Code output variable",
        port: nil,
      }
    end
  end

  def derive_node_name
    Missions::NodeVariableNameResolver.for_node(node_id, flow_data) ||
      Missions::NodeVariableNameResolver.base_name(node_data, node_id)
  end

  def build_upstream_file_variables
    upstream_variable_entries.filter_map { |entry| file_variable_from_entry(entry, node_map) }
  end

  def upstream_variable_entries
    variable_registry.available_at(node_id)
  end

  def variable_registry
    @variable_registry ||= Missions::VariableRegistry.new(flow_data)
  end

  def file_variable_from_entry(entry, node_map)
    upstream = entry.node_id && node_map[entry.node_id]
    return unless upstream && file_variable_entry?(upstream, entry)

    { name: entry.qualified_name || entry.name, description: entry.description }
  end

  def file_variable_entry?(upstream_node, entry)
    node_type = upstream_node["type"]
    return true if FILE_OUTPUT_TYPES.include?(node_type)

    node_type == "input" && input_field_is_file?(upstream_node, entry.name)
  end

  def input_field_is_file?(node, variable_name)
    Array(node.dig("data", "fields")).any? do |field|
      field["variable_name"] == variable_name && FILE_FIELD_TYPES.include?(field["field_type"])
    end
  end
end
