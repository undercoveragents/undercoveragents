# frozen_string_literal: true

class MissionNodePluginDesignerInstructions
  def initialize(node_class)
    @node_class = node_class
  end

  def call
    parts = header_parts
    append_required_fields(parts)
    append_input_schema(parts)
    append_output_variables(parts)
    append_output_ports(parts)
    parts.join("\n")
  end

  private

  attr_reader :node_class

  def header_parts
    [
      "## #{node_class.node_label} (type: \"#{node_class.node_type}\")",
      node_class.node_description,
      "",
      *singleton_parts,
    ]
  end

  def singleton_parts
    node_class.singleton? ? ["Singleton: yes (only one allowed per mission)"] : []
  end

  def append_required_fields(parts)
    return if node_class.required_field_keys.empty?

    parts << "### Required Fields"
    node_class.required_field_keys.each { |field| parts << "- `#{field}`" }
    parts << ""
  end

  def append_input_schema(parts)
    return if node_class.input_schema.empty?

    parts << "### Configuration (data fields)"
    node_class.input_schema.each do |field|
      required = field[:required] ? " (required)" : ""
      parts << "- `#{field[:name]}` (#{field[:type]}): #{field[:description]}#{required}"
    end
    parts << ""
  end

  def append_output_variables(parts)
    schema = node_class.variable_schema
    return if schema.outputs.empty?

    parts << "### Output Variables"
    schema.outputs.each do |variable|
      port_info = variable.port ? " [port: #{variable.port}]" : ""
      parts << "- `#{variable.name}` (#{variable.type}): #{variable.description}#{port_info}"
    end
    parts << ""
  end

  def append_output_ports(parts)
    ports = node_class.output_ports_for({})
    return if ports.empty?

    parts << "### Output Ports"
    ports.each { |port| parts << "- `#{port[:key]}`: #{port[:label]}" }
  end
end
