# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("tool_mission") do
  name "Mission Tool"
  version "1.0.0"
  author "Undercover Agents"
  description "Execute missions as agent tools. Maps mission input/output fields " \
              "to tool parameters automatically."
  icon "fa-solid fa-diagram-project"
  category [:tool]
  add_tool "MissionTool"
end
