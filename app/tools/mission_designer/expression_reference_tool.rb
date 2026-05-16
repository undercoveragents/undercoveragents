# frozen_string_literal: true

module MissionDesigner
  # Returns the full expression/formula reference for use when authoring
  # condition, switch, filter, or set_variable expressions. The content is
  # static so RubyLLM's built-in parameterless signature is enough.
  class ExpressionReferenceTool < RubyLLM::Tool
    description "Return the full expression/formula reference (operators, functions, variable syntax). " \
                "Call when authoring condition/switch/filter/set_variable formulas."

    def name
      "get_expression_reference"
    end

    def execute
      Missions::ExpressionDocs::FULL_REFERENCE
    end
  end
end
