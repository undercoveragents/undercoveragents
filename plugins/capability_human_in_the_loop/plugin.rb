# frozen_string_literal: true

# :nocov:

require_relative "app/services/capabilities/human_in_the_loop_plugin_hooks"

Rails.application.reloader.to_prepare { Capabilities::HumanInTheLoopPluginHooks.apply_tool_call_extension! }

UndercoverAgents::PluginSystem.register("capability_human_in_the_loop") do
  name "Human in the Loop"
  version "1.0.0"
  author "Undercover Agents"
  description "Lets agents pause, ask structured questions, and resume after the user answers in-chat."
  icon "fa-solid fa-circle-question"
  category [:capability]

  add_capability "HumanInTheLoop"
end
# :nocov:
