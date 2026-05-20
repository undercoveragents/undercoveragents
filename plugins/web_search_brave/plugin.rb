# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("web_search_brave") do
  name "Brave Web Search"
  version "1.0.0"
  author "Undercover Agents"
  description "Plugin-backed public web search client using Brave Search with connector-backed API credentials."
  icon "fa-solid fa-compass"
  category [:web_search, :connector]
  add_web_search_client "BraveSearchClient", identifier: "brave"
  add_connector "BraveSearch"
end
