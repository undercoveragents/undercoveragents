# frozen_string_literal: true

module Missions
  # Declares input/output variable metadata for a single node type.
  #
  # Used at design time to show available variables in the UI and at run time
  # to validate references. Each entry is a frozen Data struct:
  #
  #   Variable.new(name: "llm_response", type: :string, description: "LLM output text")
  #
  class VariableSchema
    Variable = Data.define(:name, :type, :description, :port) do
      def initialize(name:, type: :any, description: "", port: nil)
        super(name: name.to_s, type: type.to_sym, description: description.to_s, port: port&.to_s)
      end
    end

    attr_reader :inputs, :outputs

    # +inputs+  — Array of Variable (or hashes coerced to Variable)
    # +outputs+ — Array of Variable (or hashes coerced to Variable)
    #
    # Outputs may carry an optional +port+ field indicating they are only
    # available on a specific output handle (e.g. "loop" vs "done" on an
    # iterator).  Variables with +port: nil+ are available on all handles.
    def initialize(inputs: [], outputs: [])
      @inputs  = inputs.map  { |v| coerce(v) }.freeze
      @outputs = outputs.map { |v| coerce(v) }.freeze
    end

    def input_names
      @inputs.map(&:name)
    end

    def output_names
      @outputs.map(&:name)
    end

    # Returns outputs filtered to a specific port.
    # Variables with +port: nil+ are always included.
    def outputs_for_port(port)
      return @outputs if port.nil?

      @outputs.select { |v| v.port.nil? || v.port == port.to_s }
    end

    def to_h
      {
        inputs: @inputs.map { |v| variable_to_h(v) },
        outputs: @outputs.map { |v| variable_to_h(v) },
      }
    end

    private

    def coerce(value)
      return value if value.is_a?(Variable)

      Variable.new(**value.slice(:name, :type, :description, :port))
    end

    def variable_to_h(var)
      h = { name: var.name, type: var.type, description: var.description }
      h[:port] = var.port if var.port
      h
    end
  end
end
