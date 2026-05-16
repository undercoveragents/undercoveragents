# frozen_string_literal: true

module MissionNodePluginVariableExtraction
  def field_contract(**attributes)
    Missions::FieldContract.new(**attributes)
  end

  def add_variable(variables, seen, key, *args)
    details = variable_details(args)
    return if key.blank? || seen.include?(key)

    seen.add(key)
    variables << { key:, **details }
  end

  def extract_template_vars(variables, seen, template, label, node_type)
    return if template.blank?

    template.scan(/\{\{([\w.]+)\}\}/).flatten.each do |var_name|
      next if internal_variable_reference?(var_name)

      add_variable(variables, seen, var_name, "template", label, "Referenced in #{label || node_type} template")
    end
  end

  def extract_expression_vars(variables, seen, expression, label)
    return if expression.blank?

    expression.scan(/\{\{([\w.]+)\}\}/).flatten.each do |var_name|
      next if internal_variable_reference?(var_name)

      add_variable(variables, seen, var_name, "template", label, "Referenced in #{label} expression")
    end

    expression_identifier_tokens(expression).each do |token|
      next if skip_expression_token?(token)

      add_variable(variables, seen, token, "expression", label, "Used in expression: #{expression}")
    end
  end

  def internal_variable_reference?(name)
    normalized = name.to_s
    MissionNodePlugin::INTERNAL_VARIABLES.include?(normalized) || normalized.start_with?("_")
  end

  def skip_expression_token?(token)
    downcased = token.downcase
    token.start_with?("_") ||
      MissionNodePlugin::RESERVED_EXPRESSION_WORDS.include?(downcased) ||
      MissionNodePlugin::DENTAKU_FUNCTIONS.include?(downcased)
  end

  def extract_collection_var(variables, seen, data, label)
    collection = data["collection"]&.strip
    return unless collection.present? && collection.match?(/\A[a-z_]\w*\z/i)

    add_variable(variables, seen, collection, "expression", label, "Collection variable")
  end

  def extract_variables_from_field_contracts(node_class, data, label, variables, seen)
    context = { variables:, seen:, label: }

    node_class.field_contracts.each do |contract|
      extract_contract_value(node_class, contract, data[contract.key], context)
    end
  end

  def reference_names_from_field_contracts(node_class, data)
    refs = Set.new

    node_class.field_contracts.each do |contract|
      collect_contract_references(refs, contract, data[contract.key])
    end

    refs
  end

  def formula_field_pairs_from_contracts(node_class, data)
    node_class.field_contracts.filter_map do |contract|
      next unless contract.formula?

      value = data[contract.key]
      [contract.key, value] if value.is_a?(String) && value.present?
    end
  end

  def collection_reference_field_keys_for(node_class)
    node_class.field_contracts.select(&:collection_reference?).map(&:key)
  end

  def explicit_reference_field_contracts_for?(node_class)
    node_class.field_contracts.any?(&:reference_scannable?) ||
      node_class.field_contracts.any?(&:collection_reference?)
  end

  private

  def variable_details(args)
    options = args.last.is_a?(Hash) ? args.pop : {}
    category, source, description, input_type = args
    {
      category:,
      source:,
      description:,
      input_type: input_type || "text",
      field_type: options[:field_type],
      required: options[:required] || false,
    }
  end

  def expression_identifier_tokens(expression)
    expression
      .gsub(/\{\{[^}]*\}\}/, " ")
      .gsub(/'[^']*'/, " ")
      .gsub(/"[^"]*"/, " ")
      .scan(/\b([a-z_]\w*)\b/i)
      .flatten
  end

  def extract_contract_value(node_class, contract, value, context)
    case contract.kind
    when :template
      scan_template_value_for_variables(node_class, context[:variables], context[:seen], value, context[:label])
    when :formula
      extract_expression_vars(context[:variables], context[:seen], value.to_s, context[:label]) if value.is_a?(String)
    when :collection_ref
      add_collection_reference_variable(context[:variables], context[:seen], value, context[:label])
    when :assignment_map
      extract_assignment_map_value(node_class, value, context)
    when :input_fields
      extract_input_fields_value(value, context)
    end
  end

  def extract_assignment_map_value(node_class, value, context)
    parse_object_field(value).each do |key, expression|
      context[:seen].add(key)
      scan_template_value_for_variables(node_class, context[:variables], context[:seen], expression, context[:label])
    end
  end

  def extract_input_fields_value(value, context)
    parse_array_field(value).each do |field|
      add_input_field_variable(context[:variables], context[:seen], field, context[:label])
    end
  end

  def collect_contract_references(refs, contract, value)
    case contract.kind
    when :template, :formula
      collect_template_refs(refs, value)
    when :assignment_map
      parse_object_field(value).each_value { |entry| collect_template_refs(refs, entry) }
    end
  end

  def scan_template_value_for_variables(node_class, variables, seen, value, label)
    case value
    when String
      extract_template_vars(variables, seen, value, label, node_class.node_label)
    when Hash
      value.each_value { |entry| scan_template_value_for_variables(node_class, variables, seen, entry, label) }
    when Array
      value.each { |entry| scan_template_value_for_variables(node_class, variables, seen, entry, label) }
    end
  end

  def collect_template_refs(refs, value)
    case value
    when String
      value.scan(/\{\{([^}]+)\}\}/).flatten.each { |ref| refs.add(ref.strip) }
    when Hash
      value.each_value { |entry| collect_template_refs(refs, entry) }
    when Array
      value.each { |entry| collect_template_refs(refs, entry) }
    end
  end

  def add_collection_reference_variable(variables, seen, value, label)
    return unless value.is_a?(String)

    collection = value.strip
    return unless collection.match?(/\A[a-z_]\w*(?:\.[a-z_]\w*)*\z/i)

    add_variable(variables, seen, collection, "expression", label, "Collection variable")
  end

  def add_input_field_variable(variables, seen, field, label)
    name = field["variable_name"]
    return if name.blank?

    add_variable(
      variables,
      seen,
      name,
      "trigger",
      label,
      field["label"] || name,
      "text",
      field_type: field["field_type"] || "string",
      required: field["required"].present?,
    )
  end

  def parse_object_field(value)
    case value
    when Hash
      value
    when String
      parsed = JSON.parse(value)
      parsed.is_a?(Hash) ? parsed : {}
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def parse_array_field(value)
    case value
    when Array
      value
    when String
      parsed = JSON.parse(value)
      parsed.is_a?(Array) ? parsed : []
    else
      []
    end
  rescue JSON::ParserError
    []
  end
end
