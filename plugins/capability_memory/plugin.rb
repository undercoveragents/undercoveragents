# frozen_string_literal: true

# :nocov:

require_relative "app/services/capabilities/memory_plugin_hooks"

Rails.application.reloader.to_prepare { Capabilities::MemoryPluginHooks.apply_agent_extension! }

UndercoverAgents::PluginSystem.register("capability_memory") do
  name "Memory"
  version "1.0.0"
  author "Undercover Agents"
  description "Letta-inspired memory system with always-in-context core memory blocks " \
              "and pgvector-powered archival memory for long-term semantic retrieval."
  icon "fa-solid fa-floppy-disk"
  category [:capability]

  add_capability "Memory"
end
# :nocov:
