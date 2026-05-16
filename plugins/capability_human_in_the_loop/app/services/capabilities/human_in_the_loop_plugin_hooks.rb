# frozen_string_literal: true

module Capabilities
  module HumanInTheLoopPluginHooks
    module_function

    def apply_tool_call_extension!(tool_call_class: ToolCall,
                                   extension: Capabilities::HumanInTheLoop::ToolCallExtension)
      return if tool_call_class < extension

      tool_call_class.prepend(extension)
    end
  end
end
