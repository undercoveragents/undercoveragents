# frozen_string_literal: true

module Capabilities
  module MemoryPluginHooks
    module_function

    def apply_agent_extension!(agent_class: Agent, extension: Capabilities::Memory::AgentExtension)
      agent_class.class_eval do
        include extension unless self < extension
      end
    end
  end
end
