# frozen_string_literal: true

module MissionNodePluginNodeClassMethods
  def node_type
    name.demodulize.underscore
  end

  def node_label
    name.demodulize.titleize
  end

  def node_icon
    "fa-solid fa-circle"
  end

  def node_color
    "#6366f1"
  end

  def node_category
    :node
  end

  def node_description
    ""
  end

  def singleton?
    false
  end

  def extract_variables(data, label, variables, seen)
    MissionNodePlugin.extract_variables_from_field_contracts(self, data, label, variables, seen)
  end

  def register_node!
    MissionNodePlugin.register_from_class(self)
  end

  def variable_schema
    Missions::VariableSchema.new
  end

  def field_contracts
    []
  end

  def input_schema
    field_contracts.map do |contract|
      {
        name: contract.key,
        type: contract.value_type,
        description: contract.description,
        kind: contract.kind,
        required: contract.required?,
        json: contract.json?,
      }
    end
  end

  def field_contract(**attributes)
    MissionNodePlugin.field_contract(**attributes)
  end

  def extract_variables_from_field_contracts(data, label, variables, seen)
    MissionNodePlugin.extract_variables_from_field_contracts(self, data, label, variables, seen)
  end

  def reference_names_from_field_contracts(data)
    MissionNodePlugin.reference_names_from_field_contracts(self, data)
  end

  def formula_field_pairs_from_contracts(data)
    MissionNodePlugin.formula_field_pairs_from_contracts(self, data)
  end

  def collection_reference_field_keys
    MissionNodePlugin.collection_reference_field_keys_for(self)
  end

  def explicit_reference_field_contracts?
    MissionNodePlugin.explicit_reference_field_contracts_for?(self)
  end

  def dynamic_output_variables(_node_data)
    []
  end

  def required_field_keys
    field_contracts.select(&:required?).map(&:key)
  end

  def json_field_keys
    field_contracts.select(&:json?).map(&:key)
  end

  def default_output_ports
    [{ key: "default", label: "Output" }]
  end

  def output_ports_for(_node_data)
    default_output_ports
  end

  def strict_port_routing?
    default_output_ports.size > 1
  end

  def mutually_exclusive_output_ports?
    false
  end

  def designer_instructions
    MissionNodePluginDesignerInstructions.new(self).call
  end
end
