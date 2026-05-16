# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("capability_chat_title_generator") do
  name "Chat Title Generator"
  version "1.0.0"
  author "Undercover Agents"
  description "Automatically generates short, descriptive chat titles after each conversation turn."
  icon "fa-solid fa-heading"
  category [:capability]

  add_capability "TitleGenerator"
end
