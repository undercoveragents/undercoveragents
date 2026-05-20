# frozen_string_literal: true

UndercoverAgents::PluginSystem.register("web_search_duckduckgo") do
  name "DuckDuckGo Web Search"
  version "1.0.0"
  author "Undercover Agents"
  description "Plugin-backed public web search client using DuckDuckGo HTML results."
  icon "fa-solid fa-magnifying-glass"
  category [:web_search]
  add_web_search_client "DuckDuckGoClient", identifier: "duckduckgo", default: true
end
