# frozen_string_literal: true

# Registry and protocol for mission node types.
module MissionNodePlugin
  extend ActiveSupport::Concern
  extend MissionNodePluginRegistryMethods
  extend MissionNodePluginVariableExtraction

  RESERVED_EXPRESSION_WORDS = ["and", "or", "not", "if", "then", "else", "true", "false", "nil", "null"].freeze
  DENTAKU_FUNCTIONS = [
    "if", "min", "max", "sum", "avg", "count", "round", "roundup", "rounddown", "abs", "len", "contains",
    "concat", "left", "right", "mid", "find", "substitute", "ceil", "floor", "sqrt", "log", "switch",
    "not", "and", "or",
  ].freeze
  INTERNAL_VARIABLES = ["_current_node_data", "_nesting_depth"].freeze

  @type_map = {}
  @metadata_map = {}

  included do
    extend MissionNodePluginNodeClassMethods

    def output_ports
      self.class.default_output_ports
    end

    def validate_config!(_node_data = nil); end

    def execute(_context)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end
  end
end

MissionNodePlugin.register_defaults!
